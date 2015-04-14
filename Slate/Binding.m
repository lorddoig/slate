//
//  Binding.m
//  Slate
//
//  Created by Jigish Patel on 5/18/11.
//  Copyright 2011 Jigish Patel. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see http://www.gnu.org/licenses

#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h> /* For kVK_ constants, and TIS functions. */

#import <Foundation/Foundation.h>
#import "Binding.h"
#import "Constants.h"
#import "SlateConfig.h"
#import "StringTokenizer.h"
#import "SlateLogger.h"
#import "Operation.h"
#import "SwitchOperation.h"
#import "SlateAppDelegate.h"
#import "SnapshotOperation.h"

@implementation Binding

@synthesize op;
@synthesize keyCode;
@synthesize modifiers;
@synthesize modalKey;
@synthesize hotKeyRef;
@synthesize repeat;
@synthesize toggle;

static NSDictionary *dictionary = nil;

- (id)init {
  self = [super init];
  if (self) {
    [self setRepeat:NO];
    [self setToggle:NO];
    [self setModalKey:nil];
  }
  return self;
}

// Yes, this method is huge. Deal with it.
- (id)initWithString:(NSString *)binding {
  self = [self init];
  if (self) {
    // bind <key:modifiers|modal-key> <op> <parameters>
    NSMutableArray *tokens = [[NSMutableArray alloc] initWithCapacity:10];
    [StringTokenizer tokenize:binding into:tokens maxTokens:3];
    if ([tokens count] <=2) {
      @throw([NSException exceptionWithName:@"Unrecognized Bind" reason:binding userInfo:nil]);
    }
    [self setKeystrokeFromString:[tokens objectAtIndex:1]];
    [self setOperationAndRepeatFromString:[tokens objectAtIndex:2]];
  }

  return self;
}

- (id)initWithKeystroke:(NSString *)keystroke operation:(Operation *)op_ repeat:(BOOL)repeat_ {
  self = [self init];
  if (self) {
    [self setKeystrokeFromString:keystroke];
    [self setOp:op_];
    if ([self op] == nil) {
      SlateLogger(@"ERROR: Unable to create binding");
      @throw([NSException exceptionWithName:@"Unable To Create Binding" reason:[NSString stringWithFormat:@"Unable to create %@", keystroke] userInfo:nil]);
    }

    @try {
      AccessibilityWrapper *awTest = [[AccessibilityWrapper alloc] init];
      ScreenWrapper *swTest = [[ScreenWrapper alloc] init];
      [[self op] testOperationWithAccessibilityWrapper:awTest screenWrapper:swTest];
    } @catch (NSException *ex) {
      SlateLogger(@"ERROR: Unable to test binding");
      @throw([NSException exceptionWithName:@"Unable To Parse Binding" reason:[NSString stringWithFormat:@"Unable to parse '%@' in '%@'", [ex reason], [[self op] opName]] userInfo:nil]);
    }
    if ([[self op] isKindOfClass:[SwitchOperation class]]) {
      [(SwitchOperation *)op setModifiers:modifiers];
    }
    [self setRepeat:repeat_];
  }
  return self;
}

+ (UInt32)modifierFromString:(NSString *)mod {
  if ([mod isEqualToString:CONTROL]) {
    return controlKey;
  } else if ([mod isEqualToString:OPTION]) {
    return optionKey;
  } else if ([mod isEqualToString:COMMAND]) {
    return cmdKey;
  } else if ([mod isEqualToString:SHIFT]) {
   return shiftKey;
  } else if ([mod isEqualToString:FUNCTION]) {
    return FUNCTION_KEY;
  } else {
    SlateLogger(@"ERROR: Unrecognized modifier '%@'", mod);
    @throw([NSException exceptionWithName:@"Unrecognized Modifier" reason:[NSString stringWithFormat:@"Unrecognized modifier '%@'", mod] userInfo:nil]);
  }
}

+ (NSArray *)getKeystrokeFromString:(NSString *)keystroke {
  NSNumber *theKeyCode = [NSNumber numberWithUnsignedInt:0];
  UInt32 theModifiers = 0;
  NSNumber *theModalKey = nil;
  NSArray *keyAndModifiers = [keystroke componentsSeparatedByString:COLON];
  if ([keyAndModifiers count] >= 1) {
    NSString *theKey = [keyAndModifiers objectAtIndex:0];
    theKeyCode = [[Binding asciiToCodeDict] objectForKey:theKey];
      
    if (theKeyCode == nil && [theKey length] == 1) {
        theKeyCode = [Binding keyCodeForChar:[theKey characterAtIndex:0]];
    }
      
    if (theKeyCode == nil) {
      SlateLogger(@"ERROR: Unrecognized key \"%@\" in \"%@\"", theKey, keystroke);
      @throw([NSException exceptionWithName:@"Unrecognized Key" reason:[NSString stringWithFormat:@"Unrecognized key \"%@\" in \"%@\"", theKey, keystroke] userInfo:nil]);
    }
    if ([keyAndModifiers count] >= 2) {
      theModalKey = [[Binding asciiToCodeDict] objectForKey:[keyAndModifiers objectAtIndex:1]];
      if (theModalKey == nil) {
        // normal case
        NSArray *modifiersArray = [[keyAndModifiers objectAtIndex:1] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;"]];
        NSEnumerator *modEnum = [modifiersArray objectEnumerator];
        NSString *mod = [modEnum nextObject];
        while (mod) {
          NSNumber *_theModalKey = [[Binding asciiToCodeDict] objectForKey:mod];
          if (_theModalKey != nil) {
            theModalKey = _theModalKey;
          } else {
            theModifiers += [Binding modifierFromString:mod];
          }
          mod = [modEnum nextObject];
        }
      }
    }
  }
  return [NSArray arrayWithObjects:theKeyCode, [NSNumber numberWithInteger:theModifiers], theModalKey, nil];
}

- (void)setKeystrokeFromString:(NSString*)keystroke {
  NSArray *modalAndKey = [keystroke componentsSeparatedByString:COLON];
  if ([modalAndKey count] > 0) {
    NSArray *keyarr = [Binding getKeystrokeFromString:keystroke];
    keyCode = [[keyarr objectAtIndex:0] unsignedIntValue];
    modifiers = [[keyarr objectAtIndex:1] unsignedIntValue];
    if ([keyarr count] >= 3 ) {
      [self setModalKey:[keyarr objectAtIndex:2]];
    }
  }
  if ([modalAndKey count] >= 3){ // modal toggle
    if ([[modalAndKey objectAtIndex:2] isEqualToString:TOGGLE]) {
      [self setToggle:YES];
    }
  }
}

- (void)setOperationAndRepeatFromString:(NSString*)token {
  NSMutableString *opStr = [[NSMutableString alloc] initWithCapacity:10];
  [StringTokenizer firstToken:token into:opStr];
  BOOL theRepeat = [Operation isRepeatOnHoldOp:opStr];

  Operation *theOp = [Operation operationFromString:token];

  if (theOp == nil) {
    SlateLogger(@"ERROR: Unable to create binding");
    @throw([NSException exceptionWithName:@"Unable To Create Binding" reason:[NSString stringWithFormat:@"Unable to create '%@'", token] userInfo:nil]);
  }

  @try {
    [theOp testOperation];
  } @catch (NSException *ex) {
    SlateLogger(@"ERROR: Unable to test binding '%@'", token);
    @throw([NSException exceptionWithName:@"Unable To Parse Binding" reason:[NSString stringWithFormat:@"Unable to parse '%@' in '%@'", [ex reason], token] userInfo:nil]);
  }

  if ([theOp isKindOfClass:[SwitchOperation class]]) {
    [(SwitchOperation *)op setModifiers:modifiers];
  }

  op = theOp;
  repeat = theRepeat;
}

- (BOOL)doOperation {
  if ([(SlateAppDelegate *)[NSApp delegate] hasUndoOperation] && [op shouldTakeUndoSnapshot]) {
    [[(SlateAppDelegate *)[NSApp delegate] undoSnapshotOperation] doOperation];
  }
  @try {
    return [op doOperation];
  } @catch (NSException *ex) {
    SlateLogger(@"   ERROR %@",[ex name]);
    NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
    [alert setMessageText:[ex name]];
    [alert setInformativeText:[ex reason]];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
      SlateLogger(@"User selected exit");
      [NSApp terminate:nil];
    }
  }
  return NO;
}

- (NSString *)modalHashKey {
  if ([self modalKey] == nil) {
    return nil;
  }
  return [NSString stringWithFormat:@"%@%@%u", [self modalKey], PLUS, [self modifiers]];
}

+ (NSArray *)modalHashKeyToKeyAndModifiers:(NSString *)modalHashKey {
  NSArray *modalKeyArr = [modalHashKey componentsSeparatedByString:PLUS];
  NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
  NSNumber *theKey = [nf numberFromString:[modalKeyArr objectAtIndex:0]];
  NSNumber *theModifiers = [nf numberFromString:[modalKeyArr objectAtIndex:1]];
  return [NSArray arrayWithObjects:theKey, theModifiers, nil];
}

- (void)dealloc {
  [self setHotKeyRef:nil];
}

// This returns a dictionary containing mappings from ASCII to keyCode
+ (NSDictionary *)asciiToCodeDict {
    if (dictionary == nil) {
    dictionary = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ASCIIToCode" ofType:@"plist"]];
  }
  return dictionary;
}

+ (NSNumber *)keyCodeForChar:(const char)c {
    static CFMutableDictionaryRef charToCodeDict = NULL;
    CGKeyCode code;
    UniChar character = c;
    CFStringRef charStr = NULL;
    
    if (charToCodeDict == NULL) {
        size_t i;

        charToCodeDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 128, &kCFCopyStringDictionaryKeyCallBacks, NULL);
        if (charToCodeDict == NULL) return nil;
        
        for (i = 0; i < 128; ++i) {
            CFStringRef string = createStringForKey((CGKeyCode)i);
            if (string != NULL) {
                CFDictionaryAddValue(charToCodeDict, string, (const void *)i);
                CFRelease(string);
            }
        }
    }
    
    charStr = CFStringCreateWithCharacters(kCFAllocatorDefault, &character, 1);
    
    if (!CFDictionaryGetValueIfPresent(charToCodeDict, charStr, (const void **)&code)) {
        return nil;
    }
    CFRelease(charStr);
    
    return [NSNumber numberWithUnsignedShort:code];
}

@end

CFStringRef createStringForKey(CGKeyCode keyCode) {
    TISInputSourceRef currentKeyboard = TISCopyCurrentKeyboardInputSource();
    CFDataRef layoutData =
    TISGetInputSourceProperty(currentKeyboard,
                              kTISPropertyUnicodeKeyLayoutData);
    const UCKeyboardLayout *keyboardLayout =
    (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
    
    UInt32 keysDown = 0;
    UniChar chars[4];
    UniCharCount realLength;
    
    UCKeyTranslate(keyboardLayout,
                   keyCode,
                   kUCKeyActionDisplay,
                   0,
                   LMGetKbdType(),
                   kUCKeyTranslateNoDeadKeysBit,
                   &keysDown,
                   sizeof(chars) / sizeof(chars[0]),
                   &realLength,
                   chars);
    CFRelease(currentKeyboard);
    
    return CFStringCreateWithCharacters(kCFAllocatorDefault, chars, 1);
}
