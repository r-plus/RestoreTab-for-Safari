#import <UIKit/UIKit.h>
//#import "subjc.h"

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
-(void)_saveBackForwardListToDictionary;
-(void)_setBackURL:(id)url;
-(id)URL;
@end

@interface TabController : NSObject
-(void)clearBackForwardCaches;
@end

@interface GridTabExposeView : UIView
-(void)showRestoreButton;
@end

@interface UIApplication(restoretab)
-(void)applicationOpenURL:(id)url;
-(id)IURootViewController;
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
static BOOL isFirmware5x;
static BOOL hasEnhancedTabs;
static BOOL showingActionSheet = NO;
static int restoringStackNumber;
static id restoreButton = nil;// navigationButton for iPad 4.x

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

%new(v@:)
- (void)restoreTab
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
  NSLog(@"toggle=%@", [[killedDocuments lastObject] URLString]);
  NSLog(@"killDocDict=%d", [killedDocumentsBackForwardDict count]);
  NSLog(@"killDoc=%d", [killedDocuments count]);
#endif
  
  restoringTab = YES;
  restoringStackNumber = 1;
  id bc = [%c(BrowserController) sharedBrowserController];
  if ([bc respondsToSelector:@selector(loadURLInNewWindow:inBackground:animated:)])
    [bc loadURLInNewWindow:[[killedDocuments lastObject] URL] inBackground:NO animated:NO];
  else
    [bc loadURLInNewWindow:[[killedDocuments lastObject] URL] animated:NO];
/*
  else
    [[UIApplication sharedApplication] applicationOpenURL:[[killedDocuments lastObject] URL]];  
*/
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
    [sheet showInView:[self window]];
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
  if (isFirmware5x) {
    button = [[UIButton alloc] initWithFrame:CGRectMake(136, 0, 50, 40)];//21,22
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
    restoringTab = YES;
    restoringStackNumber = ++buttonIndex;
    id bc = [objc_getClass("BrowserController") sharedBrowserController];
    if ([bc respondsToSelector:@selector(loadURLInNewWindow:inBackground:animated:)])
      [bc loadURLInNewWindow:[[killedDocuments objectAtIndex:[killedDocuments count] - restoringStackNumber] URL] inBackground:NO animated:NO];
    else
      [bc loadURLInNewWindow:[[killedDocuments objectAtIndex:[killedDocuments count] - restoringStackNumber] URL] animated:NO];
  }
  
  showingActionSheet = NO;  
  [self release];
  self = nil;
}
@end

/////////////////////////////////////// add close tab document and update historys hook methods.

%hook TabController//compatible Sleipnizer // (quick) + (go expose) + (afterShrink) // all support!
- (void)closeTabDocument:(id)document animated:(BOOL)animated
{
  if ([document URL] != nil) {
    if ([killedDocuments lastObject] != document) {
      [killedDocuments addObject:document];
      [killedDocumentsBackForwardDict addObject:[document backForwardListDictionary]];
    }
    [button setEnabled:YES];
    [restoreButton setEnabled:YES];
#ifdef DEBUG
    NSLog(@"killDocDict=%d", [killedDocumentsBackForwardDict count]);
    NSLog(@"killDoc=%d", [killedDocuments count]);
#endif
  }
  %orig;
}
%end

%hook TabDocument
-(void)closeTabDocument // fast than above method.
{
  if ([self URL] != nil) {
    [killedDocuments addObject:self];
    [killedDocumentsBackForwardDict addObject:[self backForwardListDictionary]];
    [button setEnabled:YES];
    [restoreButton setEnabled:YES];
#ifdef DEBUG
    NSLog(@"killDocDict=%d", [killedDocumentsBackForwardDict count]);
    NSLog(@"killDoc=%d", [killedDocuments count]);
    NSLog(@"added to killBackFOrward=%@", killedDocumentsBackForwardDict);
    NSLog(@"added to killDoc=%@", killedDocuments);
#endif
  }
  %orig;
}

- (void)_updateBackForward
{
  %orig;
  
  if (restoringTab) {
#ifdef DEBUG
    NSLog(@"update if in=%@", [self backForwardListDictionary]);
    NSLog(@"removingCurrentBackForwardItem = YES");
#endif
    // this two is remove current backforwarditem.
    removingCurrentBackForwardItem = YES;
    [self backForwardListDictionary];// magic method! must need!
    
    [self setBackForwardListDictionary:[killedDocumentsBackForwardDict objectAtIndex:[killedDocumentsBackForwardDict count] - restoringStackNumber]];
    //NSLog(@"after setDict=%@", [self backForwardListDictionary]);
    [self restoreBackForwardListFromDictionary];
    //NSLog(@"after restore=%@", [self backForwardListDictionary]);  

    [self _updateBackForward];
    //NSLog(@"after update=%@", [self backForwardListDictionary]);
    
    [killedDocumentsBackForwardDict removeObjectAtIndex:[killedDocumentsBackForwardDict count] - restoringStackNumber];
    [killedDocuments removeObjectAtIndex:[killedDocuments count] - restoringStackNumber];
#ifdef DEBUG
    NSLog(@"removed_killDocDict=%d", [killedDocumentsBackForwardDict count]);
    NSLog(@"removed_killDoc=%d", [killedDocuments count]);
#endif
  }
}
%end

%hook WebBackForwardList
-(id)currentItem
{
  if (removingCurrentBackForwardItem) {
    //NSLog(@"before removeItem=%@", [self dictionaryRepresentation]);
    [self removeItem:[self itemAtIndex:0]];
    //NSLog(@"after removeItem=%@", [self dictionaryRepresentation]);
    removingCurrentBackForwardItem = NO;
    restoringTab = NO;
#ifdef DEBUG
    NSLog(@"removingCurrentBackForwardItem = NO;");
#endif
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
  isFirmware5x = [[[UIDevice currentDevice] systemVersion] hasPrefix:@"5"];
  
  dlopen("/Library/MobileSubstrate/DynamicLibraries/EnhancedTabs.dylib", RTLD_LAZY);
  Class $TabHandler = objc_getClass("TabHandler");
  hasEnhancedTabs = (class_getInstanceMethod($TabHandler, @selector(closeTabs:)) != NULL);
    
  %init;
  if (isPad) {
    if (!isFirmware5x)
      %init(restoreTabForiPad);
  } else {
    %init(restoreTabImageForiPhone);
  }
  
	[pool drain];
}

