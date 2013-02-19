//
//  NIUserInterfaceString.m
//  Nimbus
//
//  Created by Metral, Max on 2/18/13.
//  Copyright (c) 2013 Jeff Verkoeyen. All rights reserved.
//

#import "NIUserInterfaceString.h"
#import <objc/runtime.h>

static NSMutableDictionary*               sStringToViewMap;
static char                               sBaseStringAssocationKey;
static id<NIUserInterfaceStringResolver>  sResolver;

NSString* const NIStringsDidChangeNotification = @"NIStringsDidChangeNotification";
NSString* const NIStringsDidChangeFilePathKey = @"NIStringsPathKey";

////////////////////////////////////////////////////////////////////////////////
/**
 * Information about an attachment
 */
@interface NIUserInterfaceStringAttachment : NSObject
@property (unsafe_unretained,nonatomic) id element;
@property (assign) SEL setter;
@property (assign) UIControlState controlState;
@property (assign) BOOL setterIsWithControlState;
-(void)attach: (NSString*) value;
@end

////////////////////////////////////////////////////////////////////////////////
/**
 * This class exists solely to be attached to objects that strings have been
 * attached to so that we can easily detach them on dealloc
 */
@interface NIUserInterfaceStringDeallocTracker : NSObject
+(void)attachString: (NIUserInterfaceString*) string withInfo: (NIUserInterfaceStringAttachment*) attachment;
@property (strong, nonatomic) NIUserInterfaceStringAttachment *attachment;
@property (strong, nonatomic) NIUserInterfaceString *string;
@end

////////////////////////////////////////////////////////////////////////////////
@interface NIUserInterfaceStringResolverDefault : NSObject <
NIUserInterfaceStringResolver
>
// The path of a file that was loaded from Chameleon that should be checked first
// before the built in bundle
@property (nonatomic,strong) NSDictionary *overrides;
@end

////////////////////////////////////////////////////////////////////////////////
@implementation NIUserInterfaceString

+(void)setStringResolver:(id<NIUserInterfaceStringResolver>)stringResolver
{
  sResolver = stringResolver;
}

+(id<NIUserInterfaceStringResolver>)stringResolver
{
  return sResolver ?: (sResolver = [[NIUserInterfaceStringResolverDefault alloc] init]);
}

-(NSMutableDictionary*) viewMap
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sStringToViewMap = [[NSMutableDictionary alloc] init];
  });
  return sStringToViewMap;
}

////////////////////////////////////////////////////////////////////////////////
-(id)initWithKey:(NSString *)key
{
  return [self initWithKey:key defaultValue:nil];
}

-(id)initWithKey:(NSString *)key defaultValue: (NSString*) value
{
  NSString *v =[[NIUserInterfaceString stringResolver] stringForKey:key withDefaultValue:value];
  if (!v) { return nil; }
  
  self = [super init];
  if (self) {
    _string = v;
    _originalKey = key;
  }
  return self;
}

////////////////////////////////////////////////////////////////////////////////
-(void)attach:(UIView *)view
{
  if ([view respondsToSelector:@selector(setText:)]) {
    // UILabel
    [self attach: view withSelector:@selector(setText:)];
  } else if ([view respondsToSelector:@selector(setTitle:)]) {
    [self attach: view withSelector:@selector(setTitle:)];
  }
}

////////////////////////////////////////////////////////////////////////////////
-(void)attach:(id)element withSelector:(SEL)selector
{
  [self attach:element withSelector:selector withControlState:UIControlStateNormal hasControlState:NO];
}

////////////////////////////////////////////////////////////////////////////////
-(void)attach:(UIView *)view withSelector:(SEL)selector forControlState:(UIControlState)state
{
  [self attach:view withSelector:selector withControlState:state hasControlState:YES];
}

////////////////////////////////////////////////////////////////////////////////
-(void)attach:(id)element withSelector:(SEL)selector withControlState: (UIControlState) state hasControlState: (BOOL) hasControlState
{
  NIUserInterfaceStringAttachment *attachment = [[NIUserInterfaceStringAttachment alloc] init];
  attachment.element = element;
  attachment.controlState = state;
  attachment.setterIsWithControlState = hasControlState;
  attachment.setter = selector;
  
  // If we're keeping track of attachments, set all that up. Else just call the selector
  if ([[NIUserInterfaceString stringResolver] isChangeTrackingEnabled]) {
    NSMutableDictionary *viewMap =  self.viewMap;
    @synchronized (viewMap) {
      // Call this first, because if there's an existing association, it will detach it in dealloc
      [NIUserInterfaceStringDeallocTracker attachString:self withInfo:attachment];
      id existing = [viewMap objectForKey:_originalKey];
      if (!existing) {
        // Simple, no map exists, make one
        [viewMap setObject:attachment forKey:_originalKey];
      } else if ([existing isKindOfClass: [NIUserInterfaceStringAttachment class]]) {
        // An attachment exists, convert it to a list
        NSMutableArray *list = [[NSMutableArray alloc] initWithCapacity:2];
        [list addObject:existing];
        [list addObject:attachment];
        [viewMap setObject:list forKey:_originalKey];
      } else {
        // NSMutableArray*
        NSMutableArray *a = (NSMutableArray*) existing;
        [a addObject: attachment];
      }
    }
  }
  [attachment attach: _string];
}

////////////////////////////////////////////////////////////////////////////////
-(void)detach:(UIView *)view
{
  
}

-(void)detach:(id)element withSelector:(SEL)selector
{
  
}

-(void)detach:(UIView *)element withSelector:(SEL)selector forControlState:(UIControlState)state
{
  
}

-(void)detach:(id)element withSelector:(SEL)selector withControlState: (UIControlState) state hasControlState: (BOOL) hasControlState
{
  
}

@end

////////////////////////////////////////////////////////////////////////////////
@implementation NIUserInterfaceStringResolverDefault

-(id)init
{
  self = [super init];
  if (self) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stringsDidChange:) name:NIStringsDidChangeNotification object:nil];
  }
  return self;
}

-(void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)stringsDidChange: (NSNotification*) notification
{
  NSString *path = [notification.userInfo objectForKey:NIStringsDidChangeFilePathKey];
  self.overrides = [[NSDictionary alloc] initWithContentsOfFile:path];
  if (sStringToViewMap && self.overrides.count > 0) {
    @synchronized (sStringToViewMap) {
      [sStringToViewMap enumerateKeysAndObjectsUsingBlock:^(NSString* key, id obj, BOOL *stop) {
        NSString *o = [self.overrides objectForKey:key];
        if (o) {
          if ([obj isKindOfClass:[NIUserInterfaceStringAttachment class]]) {
            [((NIUserInterfaceStringAttachment*)obj) attach: o];
          } else {
            NSArray *attachments = (NSArray*) obj;
            for (NIUserInterfaceStringAttachment *a in attachments) {
              [a attach:o];
            }
          }
        }
      }];
    }
  }
}

-(NSString *)stringForKey:(NSString *)key withDefaultValue:(NSString *)value
{
  if (self.overrides) {
    NSString *overridden = [self.overrides objectForKey:key];
    if (overridden) {
      return overridden;
    }
  }
  return NSLocalizedStringWithDefaultValue(key, nil, [NSBundle mainBundle], value, nil);
}

-(BOOL)isChangeTrackingEnabled
{
#ifdef DEBUG
  return YES;
#else
  return NO;
#endif
}
@end

////////////////////////////////////////////////////////////////////////////////
@implementation NIUserInterfaceStringAttachment
-(void)attach: (NSString*) value
{
  if (self.setterIsWithControlState) {
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[_element methodSignatureForSelector:_setter]];
    [inv setSelector:_setter];
    [inv setTarget:_element];
    [inv setArgument:&value atIndex:2]; //this is the string to set (0 and 1 are self and message respectively)
    [inv setArgument:&_controlState atIndex:3];
    [inv invoke];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_element performSelector:_setter withObject:value];
#pragma clang diagnostic pop
  }
}
@end

////////////////////////////////////////////////////////////////////////////////
@implementation NIUserInterfaceStringDeallocTracker
+(void)attachString:(NIUserInterfaceString *)string withInfo:(NIUserInterfaceStringAttachment *)attachment
{
  NIUserInterfaceStringDeallocTracker *tracker = [[NIUserInterfaceStringDeallocTracker alloc] init];
  tracker.attachment = attachment;
  tracker.string = string;
  char* key = &sBaseStringAssocationKey;
  if (attachment.setterIsWithControlState) {
    key += attachment.controlState;
  }
  objc_setAssociatedObject(attachment.element, key, tracker, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(void)dealloc
{
  [self.string detach:self.attachment.element withSelector:self.attachment.setter withControlState:self.attachment.controlState hasControlState:self.attachment.setterIsWithControlState];
}
@end