#import "EnrichedTextInputView.h"
#import "interfaces/StyleHeaders.h"
#import "utils/RangeUtils.h"
#import "utils/TextListsUtils.h"

@implementation ListStyleBase

- (NSArray<NSTextList *> *)textListsByAddingValue:(NSString *)value
                                          toArray:
                                              (NSArray<NSTextList *> *)existing
                                  forcingNewLevel:(BOOL)forcingNewLevel {
  NSString *deepestFormat =
      [TextListsUtils deepestListMarkerFormatInArray:existing];

  if (!forcingNewLevel && [deepestFormat isEqualToString:value]) {
    return existing;
  }

  NSString *markerPrefix = [self getMarkerPrefix];
  if (!forcingNewLevel && markerPrefix != nil && deepestFormat != nil &&
      [deepestFormat hasPrefix:markerPrefix]) {
    return [TextListsUtils textListsByReplacingDeepestChainEntry:value
                                                         toArray:existing];
  }

  return [TextListsUtils textListsByAppendingToChain:value toArray:existing];
}

- (BOOL)styleCondition:(id)value range:(NSRange)range {
  NSParagraphStyle *pStyle = (NSParagraphStyle *)value;
  if (pStyle == nil) {
    return NO;
  }

  // check the deepest textLists marker - the nested list leaf
  NSString *ownFormat =
      [TextListsUtils deepestListMarkerFormatInArray:pStyle.textLists];
  if (ownFormat == nil) {
    return false;
  }

  NSString *markerPrefix = [self getMarkerPrefix];

  if (markerPrefix != nil) {
    return [ownFormat hasPrefix:[self getMarkerPrefix]];
  } else {
    return [ownFormat isEqualToString:[self getValue]];
  }
}

- (BOOL)isList {
  return YES;
}

- (void)add:(NSRange)range
         withValue:(NSString *)value
        withTyping:(BOOL)withTyping
    withDirtyRange:(BOOL)withDirtyRange {
  [self add:range
            withValue:value
      forcingNewLevel:NO
           withTyping:withTyping
       withDirtyRange:withDirtyRange];
}

- (void)add:(NSRange)range
          withValue:(NSString *)value
    forcingNewLevel:(BOOL)forcingNewLevel
         withTyping:(BOOL)withTyping
     withDirtyRange:(BOOL)withDirtyRange {
  NSRange actualRange = [self actualUsedRange:range];

  [self.host.textView.textStorage
      enumerateAttribute:NSParagraphStyleAttributeName
                 inRange:actualRange
                 options:0
              usingBlock:^(id _Nullable existingValue, NSRange subRange,
                           BOOL *_Nonnull stop) {
                NSParagraphStyle *currentStyle =
                    (NSParagraphStyle *)existingValue;
                if (currentStyle == nil)
                  return;

                NSArray<NSTextList *> *updatedTextLists =
                    [self textListsByAddingValue:value
                                         toArray:currentStyle.textLists
                                 forcingNewLevel:forcingNewLevel];
                if (updatedTextLists == currentStyle.textLists) {
                  return;
                }

                NSMutableParagraphStyle *pStyle = [currentStyle mutableCopy];
                pStyle.textLists = updatedTextLists;
                [self.host.textView.textStorage
                    addAttribute:NSParagraphStyleAttributeName
                           value:pStyle
                           range:subRange];
              }];

  if (withTyping) {
    [self addTypingWithValue:value forcingNewLevel:forcingNewLevel];
  }

  // Notify attributes manager of styling to be re-done if needed.
  if (withDirtyRange) {
    [self.host.attributesManager addDirtyRange:actualRange];
  }
}

- (void)toggle:(NSRange)range withConflictReplaced:(BOOL)conflictReplaced {
  // during the toggle, a conflicting style (a different list)
  // might have been removed. If so, we just add a new value to
  // the textLists. Otherwise we follow the base flow
  if (!conflictReplaced) {
    [self toggle:range];
    return;
  }
  [self add:[self actualUsedRange:range]
            withValue:[self getValue]
      forcingNewLevel:YES
           withTyping:YES
       withDirtyRange:YES];
}

- (void)remove:(NSRange)range withDirtyRange:(BOOL)withDirtyRange {
  NSRange actualRange = [self actualUsedRange:range];

  [self.host.textView.textStorage
      enumerateAttribute:NSParagraphStyleAttributeName
                 inRange:actualRange
                 options:0
              usingBlock:^(id _Nullable existingValue, NSRange subRange,
                           BOOL *_Nonnull stop) {
                NSMutableParagraphStyle *pStyle =
                    [(NSParagraphStyle *)existingValue mutableCopy];
                if (pStyle == nullptr)
                  return;
                pStyle.textLists = [TextListsUtils
                    textListsByRemovingDeepestChainEntry:pStyle.textLists];
                [self.host.textView.textStorage
                    addAttribute:NSParagraphStyleAttributeName
                           value:pStyle
                           range:subRange];
              }];
  [self removeTyping];

  // Notify attributes manager of styling to be re-done if needed.
  if (withDirtyRange) {
    [self.host.attributesManager addDirtyRange:actualRange];
  }
}

- (void)addTypingWithValue:(NSString *)value {
  [self addTypingWithValue:value forcingNewLevel:NO];
}

- (void)addTypingWithValue:(NSString *)value
           forcingNewLevel:(BOOL)forcingNewLevel {
  NSMutableDictionary *newTypingAttrs =
      [self.host.textView.typingAttributes mutableCopy];

  NSParagraphStyle *currentStyle =
      newTypingAttrs[NSParagraphStyleAttributeName];
  if (currentStyle == nil)
    return;

  NSArray<NSTextList *> *updatedTextLists =
      [self textListsByAddingValue:value
                           toArray:currentStyle.textLists
                   forcingNewLevel:forcingNewLevel];
  if (updatedTextLists == currentStyle.textLists) {
    return;
  }

  NSMutableParagraphStyle *pStyle = [currentStyle mutableCopy];
  pStyle.textLists = updatedTextLists;
  newTypingAttrs[NSParagraphStyleAttributeName] = pStyle;
  self.host.textView.typingAttributes = newTypingAttrs;
}

- (void)removeTyping {
  NSMutableDictionary *newTypingAttrs =
      [self.host.textView.typingAttributes mutableCopy];
  NSMutableParagraphStyle *pStyle =
      [newTypingAttrs[NSParagraphStyleAttributeName] mutableCopy];
  if (pStyle == nil)
    return;
  pStyle.textLists =
      [TextListsUtils textListsByRemovingDeepestChainEntry:pStyle.textLists];
  newTypingAttrs[NSParagraphStyleAttributeName] = pStyle;
  self.host.textView.typingAttributes = newTypingAttrs;
}

- (void)reapplyFromStylePair:(StylePair *)pair {
  NSRange range = [pair.rangeValue rangeValue];
  [self add:range withTyping:NO withDirtyRange:NO];
  // restore nested list metadata
  [self restoreListChainFromStylePair:pair range:range];
}

- (CGFloat)cumulativeHeadIndentForChain:(NSArray<NSTextList *> *)chain {
  CGFloat total = 0;
  for (NSTextList *entry in chain) {
    NSString *format = entry.markerFormat;
    if ([format isEqualToString:@"EnrichedUnorderedList"]) {
      total += [self.host.config unorderedListMarginLeft] +
               [self.host.config unorderedListGapWidth];
    } else if ([format isEqualToString:@"EnrichedOrderedList"]) {
      total += [self.host.config orderedListMarginLeft] +
               [self.host.config orderedListGapWidth];
    } else if ([format hasPrefix:@"EnrichedCheckbox"]) {
      total += [self.host.config checkboxListMarginLeft] +
               [self.host.config checkboxListGapWidth] +
               [self.host.config checkboxListBoxSize];
    }
  }
  return total;
}

- (NSArray<NSTextList *> *)textListsAtParagraphRange:(NSRange)paragraphRange {
  NSParagraphStyle *pStyle;
  if (paragraphRange.length == 0) {
    pStyle = self.host.textView.typingAttributes[NSParagraphStyleAttributeName];
  } else {
    pStyle =
        [self.host.textView.textStorage attribute:NSParagraphStyleAttributeName
                                          atIndex:paragraphRange.location
                                   effectiveRange:NULL];
  }
  return pStyle.textLists;
}

- (void)modifyListNestingInRange:(NSRange)range
                      increasing:(BOOL)increasingNesting {
  NSRange actualRange = [self actualUsedRange:range];
  NSArray<NSValue *> *paragraphRanges =
      [RangeUtils getSeparateParagraphsRangesIn:self.host.textView
                                          range:actualRange];

  for (NSValue *paragraphRangeValue in paragraphRanges) {
    NSRange paragraphRange = [paragraphRangeValue rangeValue];
    NSArray<NSTextList *> *textLists =
        [self textListsAtParagraphRange:paragraphRange];

    if (increasingNesting) {
      NSString *ownFormat =
          [TextListsUtils deepestListMarkerFormatInArray:textLists];
      if (ownFormat == nil || paragraphRange.location == 0) {
        continue;
      }

      // we look at the line before, to inherit the parent list's textLists
      NSRange prevRange = [self.host.textView.textStorage.string
          paragraphRangeForRange:NSMakeRange(paragraphRange.location - 1, 0)];
      NSArray<NSTextList *> *prevChain = [TextListsUtils
          listChainInArray:[self textListsAtParagraphRange:prevRange]];
      NSUInteger currentDepth = [TextListsUtils listDepthInArray:textLists];
      if (prevChain.count < currentDepth) {
        continue;
      }

      for (NSUInteger i = 0; i < currentDepth; i++) {
        [self remove:paragraphRange withDirtyRange:NO];
      }

      for (NSUInteger i = 0; i < currentDepth; i++) {
        [self add:paragraphRange
                  withValue:prevChain[i].markerFormat
            forcingNewLevel:YES
                 withTyping:YES
             withDirtyRange:NO];
      }

      [self add:paragraphRange
                withValue:ownFormat
          forcingNewLevel:YES
               withTyping:YES
           withDirtyRange:YES];
    } else if ([TextListsUtils listDepthInArray:textLists] > 1) {
      [self remove:paragraphRange withDirtyRange:YES];
    }
  }
}

@end
