#import <UIKit/UIKit.h>
#import "Firmware.h"

#define BC [%c(BrowserController) sharedBrowserController]
//#define DEBUG

/////// for "RestoreTab" feature start
@interface BrowserController : NSObject//WebUIController
+ (id)sharedBrowserController;
- (void)loadURLInNewWindow:(id)url animated:(BOOL)animate;//ios4
-(id)loadURLInNewWindow:(id)newWindow inBackground:(BOOL)background animated:(BOOL)animated;//ios5
- (id)buttonBar;
- (id)transitionView;
- (id)tabController;
- (int)allDocumentCount;
- (void)setShowingTabs:(BOOL)arg;
-(id)_modalViewController;
-(void)updateInterface:(BOOL)arg;
@end

@interface WebBackForwardList : NSObject
- (id)removeItem:(id)arg;
- (id)dictionaryRepresentation;
- (id)itemAtIndex:(int)arg;
@end

@interface TabDocument : NSObject
-(id)URLString;
-(void)setBackForwardListDictionary:(id)dictionary;
-(id)title;
-(id)backForwardListDictionary;
-(void)_updateBackForward;
-(void)clearBackForwardCache;
-(void)restoreBackForwardListFromDictionary;
-(void)becameActive;
-(void)_saveBackForwardListToDictionary;
-(void)_setBackURL:(id)url;
-(id)URL;
@end

@interface TabController : NSObject
-(void)setActiveTabDocument:(id)document animated:(BOOL)animated;
-(TabDocument *)activeTabDocument;
-(void)clearBackForwardCaches;
-(void)_updateDocumentIndex;
-(void)animateAddNewTabDocument:(id)tab;
-(NSArray *)tabDocuments;
@end

@interface GridTabExposeView : UIView
-(void)showRestoreButton;
@end

@interface PagedTabExposeView : UIView
@property(readonly, assign, nonatomic, getter=isShowing) BOOL showing;
@end

@interface UIApplication(restoretab)
-(void)applicationOpenURL:(id)url;
-(id)IURootViewController;
-(void)restoreTabFromSleipnizer:(BOOL)arg;
@end

@interface RestoreSheet : NSObject <UIActionSheetDelegate>
@end

static id button = nil;
static id buttonBar = nil;
static NSMutableArray *killedDocuments = [[NSMutableArray alloc] init];
static NSMutableArray *killedDocumentsBackForwardDict = [[NSMutableArray alloc] init];

static BOOL restoringTab = NO;
static BOOL removingCurrentBackForwardItem = NO;
static BOOL isFirmware4x;
static BOOL isFirmware5Plus;
static BOOL isFirmware6Plus;
static BOOL hasEnhancedTabs;
static BOOL showingActionSheet = NO;
static int restoringStackNumber;
static id restoreButton = nil;// navigationButton for iPad 4.x
static TabDocument *restoredTab = nil;

static inline void Alert(NSString *message)
{
	UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"RestoreTab" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[av show];
	[av release];
}

%group restoreTabImageForiPhone
%hook BrowserController
-(void)setShowingTabs:(BOOL)tabs
{
  if ([killedDocuments count] == 0)
    [button setEnabled:NO];
  else
    [button setEnabled:YES];
    
  if (isFirmware4x) {    
    UIBarButtonItem *fs = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    NSArray *items;
    NSArray *languages = [NSLocale preferredLanguages];
    NSString *currentLanguage = [[languages objectAtIndex:0] substringToIndex:2];  
    
    if (hasEnhancedTabs) { //vi hu ca en-GB ro he el cs hr ar tr pl ko sv nb fi da pt es it pt-PT de en ja
      if ([currentLanguage isEqualToString:@"th"] || [currentLanguage isEqualToString:@"zh"]){
        items = [[NSArray alloc] initWithObjects:fs, fs, fs, fs, button, fs, fs, nil];
      }
      else if (![currentLanguage isEqualToString:@"ms"] && ![currentLanguage isEqualToString:@"id"] && ![currentLanguage isEqualToString:@"sk"]
               && ![currentLanguage isEqualToString:@"ru"] && ![currentLanguage isEqualToString:@"nl"] && ![currentLanguage isEqualToString:@"fr"]
               && ![currentLanguage isEqualToString:@"uk"]){
        items = [[NSArray alloc] initWithObjects:fs, fs, button, fs, fs, fs, fs, nil];
      }
      else {
        items = [[NSArray alloc] initWithObjects:fs, button, fs, nil];
      }
    } else { //ms id sk ru nl fr uk 
      items = [[NSArray alloc] initWithObjects:fs, button, fs, nil];
    }
    
    tabs ? [buttonBar setItems:items animated:YES] : [buttonBar setItems:nil animated:YES];
    
    [fs release];
    [items release];
  } else { // iOS 5x
/*    NSLog(@"frame = %@", NSStringFromCGRect([button frame]));*/
    CGRect frame = ((UIView *)button).frame;
    frame.origin.x = MSHookIvar<UIView *>(BC, "_pageView").frame.size.width / 2.0f - 20.0f;
    ((UIView *)button).frame = frame;
/*    NSLog(@"after frame = %@", NSStringFromCGRect([button frame]));*/
    tabs ? [buttonBar addSubview:button] : [button removeFromSuperview];  
  }
  
  %orig;
}
%end
%end

///////////////////////////////////////////for iPad 4x
%group restoreTabForiPad
%hook GridTabExposeView//:UIView

%new(v@:)
-(void)showRestoreButton
{
  if (restoreButton == nil) {
    id app = [%c(Application) sharedApplication];
    restoreButton = [[%c(UINavigationButton) alloc] initWithTitle:@"RestoreTab"];
    [restoreButton addTarget:app action:@selector(restoreTab) forControlEvents:UIControlEventTouchUpInside];
    UIButton *dim = MSHookIvar<UIButton*>(self, "_newTabButton");
    UILongPressGestureRecognizer *holdGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:app action:@selector(restoreButtonHeld:)];
    [restoreButton addGestureRecognizer:holdGesture];
    [holdGesture release];

    [restoreButton setFrame:CGRectMake(dim.frame.size.width / 2.0f, 0.0f, dim.frame.size.width / 2.0f, 30.0f)];

    ([killedDocuments count] == 0) ? [restoreButton setEnabled:NO] : [restoreButton setEnabled:YES];
    
    [dim addSubview:restoreButton];
  }
}

-(void)showAfterView:(id)view
{
  %orig;
  [self showRestoreButton];
}
-(void)tile
{
  %orig;
  [restoreButton removeFromSuperview];
  restoreButton = nil;
  [self showRestoreButton];
}
%end
%end
///////////////////////////////////////////end for iPad 4x

%hook Application

static inline void LoadURLFromStackThenMoveTab(id URL, BOOL fromSleipnizer)
{
  restoringTab = YES;
  id bc = [objc_getClass("BrowserController") sharedBrowserController];
  restoredTab = nil;
  if ([bc respondsToSelector:@selector(loadURLInNewWindow:inBackground:animated:)])
    restoredTab = [bc loadURLInNewWindow:URL inBackground:NO animated:NO];
  else
    [bc loadURLInNewWindow:URL animated:NO];

  if (isFirmware6Plus && !fromSleipnizer) {
    id tabController = [bc tabController];
    id tabExposeView = MSHookIvar<id>(tabController, "_tabExposeView");
    [tabExposeView _updateDocumentIndex];
    [tabExposeView animateAddNewTabDocument:restoredTab];

    [tabController setActiveTabDocument:restoredTab animated:NO];
    [[tabController activeTabDocument] becameActive];
    [bc updateInterface:YES];
  }
}

%new(v@:)
- (void)restoreTab { 
  id tabController = [BC tabController];
  id tabExposeView = MSHookIvar<id>(tabController, "_tabExposeView");
/*  NSLog(@"isShowing = %@", [tabExposeView isShowing] ? @"YES" : @"NO");*/
  if ([tabExposeView respondsToSelector:@selector(isShowing)] && [tabExposeView isShowing])
    [self restoreTabFromSleipnizer:NO];
  else
    [self restoreTabFromSleipnizer:YES];
}

%new(v@:)
- (void)restoreTabFromSleipnizer:(BOOL)fromSleipnizer
{
  if (restoringTab) {
    Alert(@"Now restoring. Please wait little.");
    return;
  }
  if ([killedDocuments count] == 0 || [killedDocumentsBackForwardDict count] == 0) {
    Alert(@"Nothing stored tabs.");
    return;
  }
    
#ifdef DEBUG
  NSLog(@"lastObject url=%@", [[killedDocuments lastObject] URLString]);
  NSLog(@"killDocDict=%d", [killedDocumentsBackForwardDict count]);
  NSLog(@"killDoc=%d", [killedDocuments count]);
#endif
  
  restoringStackNumber = 1;
  LoadURLFromStackThenMoveTab([[killedDocuments lastObject] URL], fromSleipnizer);
}

%new(v@:@)
- (void)restoreButtonHeld:(UILongPressGestureRecognizer *)sender
{
  if (restoringTab) {
    Alert(@"Now restoring. Please wait little.");
    return;
  }
  if (!showingActionSheet) {
    showingActionSheet = YES;
    RestoreSheet *rs = [[RestoreSheet alloc] init];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:rs cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet setAlertSheetStyle:UIBarStyleBlackTranslucent];
    for (TabDocument *doc in [killedDocuments reverseObjectEnumerator])
      [sheet addButtonWithTitle:[doc title]];
    [sheet setCancelButtonIndex:[sheet addButtonWithTitle:@"Cancel"]];
/*    [sheet showInView:[self window]];*/
    [sheet showInView:MSHookIvar<id>(BC, "_pageView")];
    [sheet release];
  }
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	%orig;
  
  // initialize buttonBar for addSubview.
  // Class:
  //    iOS4: BrowserButtonBar:UIToolBar:UIView:UIResponder:NSObject
  //    iOS5: BrowserToolbar:UIToolbar:UIView:UIResponder:NSObject
	buttonBar = [[%c(BrowserController) sharedBrowserController] buttonBar];
    
  // initialize icon button.
  UILongPressGestureRecognizer *holdGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(restoreButtonHeld:)];
  if (isFirmware5Plus) {
    button = [[UIButton alloc] initWithFrame:CGRectMake(136, 0, 50, 40)];//136
    ((UIView *)button).autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [button setImage:[UIImage imageNamed:@"RestoreTab.png"] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(restoreTab) forControlEvents:UIControlEventTouchUpInside];
    [button setShowsTouchWhenHighlighted:YES];
    [button addGestureRecognizer:holdGesture];
  } else {
    UIButton *customView = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 21, 22)];//27,22
    [customView setBackgroundImage:[UIImage imageNamed:@"RestoreTab.png"] forState:UIControlStateNormal];
    [customView addTarget:self action:@selector(restoreTab) forControlEvents:UIControlEventTouchUpInside];
    [customView setShowsTouchWhenHighlighted:YES];
    button = [[UIBarButtonItem alloc] initWithCustomView:customView];
    [customView addGestureRecognizer:holdGesture];
  }
  [holdGesture release];
#ifdef Covert  
  //// Covert button style
	button = [[%c(UINavigationButton) alloc] initWithTitle:@"RestoreTab"];
  button = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemAction target:self action:@selector(restoreTab)];
  [button addTarget:self action:@selector(restoreTab) forControlEvents:UIControlEventTouchUpInside];
	[buttonBar setFrame:[buttonBar frame]];
#endif
}
%end

@implementation RestoreSheet
- (void)actionSheet:(UIActionSheet*)sheet clickedButtonAtIndex:(int)buttonIndex
{
  if (buttonIndex != [sheet cancelButtonIndex]) {
    restoringStackNumber = ++buttonIndex;
    LoadURLFromStackThenMoveTab([[killedDocuments objectAtIndex:[killedDocuments count] - restoringStackNumber] URL], NO);
  }
  
  showingActionSheet = NO;  
  [self release];
  self = nil;
}
@end

/////////////////////////////////////// add close tab document and update historys hook methods.

static inline void SaveBackForwardHistory(TabDocument *tab)
{
  if ([tab URL] != nil) {
    if ([killedDocuments lastObject] != tab) {
      [killedDocuments addObject:tab];
      [killedDocumentsBackForwardDict addObject:[tab backForwardListDictionary]];
    }
    [button setEnabled:YES];
    [restoreButton setEnabled:YES];
#ifdef DEBUG
    NSLog(@"killDocDict=%d", [killedDocumentsBackForwardDict count]);
    NSLog(@"killDoc=%d", [killedDocuments count]);
#endif
  }
}

%hook TabController//compatible Sleipnizer // (quick) + (go expose) + (afterShrink) // all support!
- (void)closeTabDocument:(TabDocument *)tab animated:(BOOL)animated
{
  SaveBackForwardHistory(tab);
  %orig;
}
%end

%hook TabDocument
// until iOS 6.
-(void)closeTabDocument // fast than above method.
{
  SaveBackForwardHistory(self);
  %orig;
}

// restore the BackForward History!
/////////////////////////////////////////////////////////////////////////////

static inline void UpdateBackForward(TabDocument *self)
{
  if (restoringTab) {
#ifdef DEBUG
    NSLog(@"update if in=%@", [self backForwardListDictionary]);
    NSLog(@"removingCurrentBackForwardItem = YES");
#endif
    // this two is remove current backforwarditem.
    removingCurrentBackForwardItem = YES;
    if (!isFirmware6Plus)
      [self backForwardListDictionary];// magic method! must need! ... no longer necesarry on iOS 6.
    else
      restoringTab = NO; // current(loaded url) history delete timing is changed in iOS 6. So change the restoringTab set to NO timing `currentItem` to this function for iOS 6.
    
    [self setBackForwardListDictionary:[killedDocumentsBackForwardDict objectAtIndex:[killedDocumentsBackForwardDict count] - restoringStackNumber]];
    //NSLog(@"after setDict=%@", [self backForwardListDictionary]);
    [self restoreBackForwardListFromDictionary];
    //NSLog(@"after restore=%@", [self backForwardListDictionary]);  

    if ([self respondsToSelector:@selector(_updateBackForward)])
      [self _updateBackForward];
    //NSLog(@"after update=%@", [self backForwardListDictionary]);
/*    id toolbar = MSHookIvar<id>(BC, "_buttonBar");*/
/*    [toolbar updateButtonsAnimated:YES];*/
    if (isFirmware6Plus) {
      id loadingController = MSHookIvar<id>(self, "_loadingController");
      [loadingController _updateBackForward];
    }
    
    [killedDocumentsBackForwardDict removeObjectAtIndex:[killedDocumentsBackForwardDict count] - restoringStackNumber];
    [killedDocuments removeObjectAtIndex:[killedDocuments count] - restoringStackNumber];
#ifdef DEBUG
    NSLog(@"removed_killDocDict=%d", [killedDocumentsBackForwardDict count]);
    NSLog(@"removed_killDoc=%d", [killedDocuments count]);
#endif
  }
}

// this method until iOS 5
- (void)_updateBackForward
{
  %orig;
  UpdateBackForward(self);
}
%end

// new _updateBackForward in iOS 6!
%hook WebUIBrowserLoadingController
- (void)_updateBackForward
{
  %orig;
/*  UpdateBackForward([[[BC tabController] tabDocuments] lastObject]);*/
/*  for (TabDocument *tab in [[BC tabController] tabDocuments]) {*/
/*    NSLog(@"tab = %@, title = %@", tab, [tab title]);*/
/*  }*/
/*  NSLog(@"restoredTab = %@, title = %@", restoredTab, [restoredTab title]);*/
  UpdateBackForward(restoredTab);
}
%end

// current ( loaded url ) history delete.
/////////////////////////////////////////////////////////////////////////////

%hook WebBackForwardList
-(id)currentItem
{
#ifdef DEBUG
  %log;
  NSLog(@"current =%@", [self dictionaryRepresentation]);
#endif
  if (removingCurrentBackForwardItem) {
    //NSLog(@"before removeItem=%@", [self dictionaryRepresentation]);
    if (!isFirmware6Plus) {
      [self removeItem:[self itemAtIndex:0]];
      restoringTab = NO; // set to NO timing changed since iOS6. goto UpdateBackForward function.
    }
    //NSLog(@"after removeItem=%@", [self dictionaryRepresentation]);
    removingCurrentBackForwardItem = NO;
#ifdef DEBUG
    NSLog(@"removingCurrentBackForwardItem = NO;");
#endif
  }

  // remove loaded url history for iOS 6.
  if (isFirmware6Plus && restoringTab) {
    //NSLog(@"IOS6!!!! before removeItem=%@", [self dictionaryRepresentation]);
    [self removeItem:[self itemAtIndex:0]];
    //NSLog(@"IOS&!!!! after removeItem=%@", [self dictionaryRepresentation]);
  }
  return %orig;
}
%end


///////////////////// Constructor
%ctor
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  static BOOL isPad = [[[UIDevice currentDevice] model] isEqualToString:@"iPad"];
  isFirmware4x = [[[UIDevice currentDevice] systemVersion] hasPrefix:@"4"];
  isFirmware5Plus = (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_5_0) ? YES : NO;
  isFirmware6Plus = (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_6_0) ? YES : NO;
  
  dlopen("/Library/MobileSubstrate/DynamicLibraries/EnhancedTabs.dylib", RTLD_LAZY);
  Class $TabHandler = objc_getClass("TabHandler");
  hasEnhancedTabs = (class_getInstanceMethod($TabHandler, @selector(closeTabs:)) != NULL);
    
  %init;
  if (isPad) {
    if (!isFirmware5Plus)
      %init(restoreTabForiPad);
  } else {
    %init(restoreTabImageForiPhone);
  }
  
	[pool drain];
}

