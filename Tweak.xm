#import <UIKit/UIKit.h>
#import <Firmware.h>

#define BC [%c(BrowserController) sharedBrowserController]
//#define DEBUG 1
#import <debug.h>

// Headers {{{
static inline void LoadURLFromStackThenMoveTab(id URL, BOOL fromSleipnizer);
/////// for "RestoreTab" feature start
@interface UIBarButtonItem()
- (UIView *)view;
@end

@interface CloudTabDevice : NSObject
@property(readonly, nonatomic) NSArray *tabs;
- (id)_initWithDictionary:(id)arg1 UUID:(id)arg2;
@end

@interface CloudTabHeaderView : UIView
@property(copy, nonatomic) NSString *text;
@end

@interface BrowserController : NSObject//WebUIController
+ (id)sharedBrowserController;
- (id)_tiltedTabToolbar;
- (void)loadURLInNewWindow:(id)url animated:(BOOL)animate;//ios4
- (id)loadURLInNewWindow:(id)newWindow inBackground:(BOOL)background animated:(BOOL)animated;//ios5
- (id)buttonBar;
- (id)transitionView;
- (id)tabController;
- (int)allDocumentCount;
- (void)setShowingTabs:(BOOL)arg;
- (id)_modalViewController;
- (void)updateInterface:(BOOL)arg;
@end

@interface WebBackForwardList : NSObject
- (id)removeItem:(id)arg;
- (id)dictionaryRepresentation;
- (id)itemAtIndex:(int)arg;
@end

@interface TabDocument : NSObject
- (id)URLString;
- (void)setBackForwardListDictionary:(id)dictionary;
- (id)title;
- (id)backForwardListDictionary;
- (void)_updateBackForward;
- (void)clearBackForwardCache;
- (void)restoreBackForwardListFromDictionary;
- (void)becameActive;
- (void)_saveBackForwardListToDictionary;
- (void)_setBackURL:(id)url;
- (id)URL;
@end

@interface TabController : NSObject
- (void)setActiveTabDocument:(id)document animated:(BOOL)animated;
- (void)_updateTiltedTabViewCloudTabs;
- (void)_dismissTiltedTabView;
- (TabDocument *)activeTabDocument;
- (void)clearBackForwardCaches;
- (void)_updateDocumentIndex;
- (void)animateAddNewTabDocument:(id)tab;
- (NSArray *)tabDocuments;
@end

@interface GridTabExposeView : UIView
- (void)showRestoreButton;
@end

@interface PagedTabExposeView : UIView
@property(readonly, assign, nonatomic, getter=isShowing) BOOL showing;
@end

@interface UIApplication(restoretab)
- (void)applicationOpenURL:(id)url;
- (id)IURootViewController;
- (void)restoreTabFromSleipnizer:(BOOL)arg;
@end

@interface RestoreSheet : NSObject <UIActionSheetDelegate>
@end
// }}}

// global var {{{
static id button = nil;
static id buttonBar = nil;
// stored many TabDocument objects.
static NSMutableArray *killedDocuments = [[NSMutableArray alloc] init];
static NSMutableArray *killedDocumentsBackForwardDict = [[NSMutableArray alloc] init];

static BOOL restoringTab = NO;
static BOOL removingCurrentBackForwardItem = NO;
static BOOL isFirmware4x;
static BOOL isFirmware5Plus;
static BOOL isFirmware6Plus;
static BOOL hasEnhancedTabs = NO;
static int restoringStackNumber;
static id restoreButton = nil;// navigationButton for iPad 4.x
static TabDocument *restoredTab = nil;
// }}}

static inline void Alert(NSString *message)
{
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"RestoreTab" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [av show];
    [av release];
}

// add invoke interface for iOS 7 {{{
%group iOS_ge_7
%hook BrowserController
- (void)_initSubviews
{
    %orig;
    UIToolbar *bar = [self _tiltedTabToolbar];
    for (UIBarButtonItem *item in bar.items) {
        Log(@"%@", item);
        if (item.action == @selector(_addNewActiveTiltedTabViewTab)) {
            // TODO: add longpress gesture
            Log(@"this is + button");
            UILongPressGestureRecognizer *holdGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication] action:@selector(restoreButtonHeld:)];
            [[item view] addGestureRecognizer:holdGesture];
            [holdGesture release];
            break;
        }
    }
}
%end //End of Browsercontroller hook

/*
   DeviceName = i5;
   LastModified = "2014-02-11 11:25:47 +0000";
   Tabs =     (
       {
           Title = Apple;
           URL = "http://www.apple.com/";
       },
       ...
   );
*/
%hook TiltedTabView
static NSUInteger originalCloudItemCount;
// NSArray[CloudTabDevice,...]
- (void)setCloudTabDevices:(NSArray *)devices
{
    if (killedDocuments.count == 0)
        return %orig;

    NSMutableArray *array = [NSMutableArray array];
    for (TabDocument *tab in [killedDocuments reverseObjectEnumerator])
        [array addObject:@{@"Title":[tab title], @"URL":[tab URLString]}];

    originalCloudItemCount = devices.count;
    for (CloudTabDevice *i in devices)
        originalCloudItemCount += [[i tabs] count];
    Log(@"originalCloudItemCount = %ld", originalCloudItemCount);

    id restoreTabDevice = [[%c(CloudTabDevice) alloc] _initWithDictionary:@{@"DeviceName":@"RestoreTab", @"LastModified":[NSDate date], @"Tabs":[NSArray arrayWithArray:array]} UUID:@"X"];
    %orig([devices arrayByAddingObject:restoreTabDevice]);
}

// arg = CloudTabItemView
- (void)_didSelectCloudTabItemView:(id)arg1
{
    NSUInteger selectedCloudTabIndex = [MSHookIvar<NSMutableArray *>(self, "_cloudTabViews") indexOfObject:arg1];
    Log(@"selectedCloudTabIndex = %ld", (unsigned long)selectedCloudTabIndex);
    Log(@"originalCloudItemCount = %ld", (unsigned long)originalCloudItemCount);
    if (killedDocuments.count && selectedCloudTabIndex > originalCloudItemCount) {
        if (restoringTab || selectedCloudTabIndex - originalCloudItemCount > killedDocuments.count) {
            Alert(@"Now restoring. Please wait little.");
            return;
        }
        restoringStackNumber = selectedCloudTabIndex - originalCloudItemCount;
        LoadURLFromStackThenMoveTab([[killedDocuments objectAtIndex:[killedDocuments count] - restoringStackNumber] URL], NO);
    } else {
        %orig;
    }
}
%end // End of TiltedTabView hook

%hook CloudTabHeaderView
- (void)setText:(NSString *)text
{
    %orig;
    if ([self.text isEqualToString:@"RestoreTab"]) {
        UIImageView *&_icon = MSHookIvar<UIImageView *>(self, "_icon");
        _icon.image = [UIImage imageNamed:@"RestoreTab"];
    }
}
%end // End of CloudTabHeaderView
%end // End of group
//}}}
// addSubview button for iPhone <= 6.x {{{
%group iOS_le_6
%hook BrowserController
- (void)setShowingTabs:(BOOL)tabs
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
%end // }}}
///////////////////////////////////////////for iPad 4x {{{
%group restoreTabForiPad
%hook GridTabExposeView//:UIView

%new
- (void)showRestoreButton
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

- (void)showAfterView:(id)view
{
    %orig;
    [self showRestoreButton];
}
- (void)tile
{
    %orig;
    [restoreButton removeFromSuperview];
    restoreButton = nil;
    [self showRestoreButton];
}
%end
%end
///////////////////////////////////////////end for iPad 4x }}}

static inline void SwitchToTab(id tab)
{
    id bc = [objc_getClass("BrowserController") sharedBrowserController];
    TabController *tabController = [bc tabController];
    [tabController setActiveTabDocument:tab animated:NO];
    [[tabController activeTabDocument] becameActive];
    [bc updateInterface:YES];
}

static inline void LoadURLFromStackThenMoveTab(id URL, BOOL fromSleipnizer)
{
    Log(@"LoadURLFromStackThenMoveTab: URL = %@, fromSleipnizer = %d", URL, fromSleipnizer);
    restoringTab = YES;
    id bc = [objc_getClass("BrowserController") sharedBrowserController];
    restoredTab = nil;
    if ([bc respondsToSelector:@selector(loadURLInNewWindow:inBackground:animated:)])
        restoredTab = [bc loadURLInNewWindow:URL inBackground:NO animated:NO];
    else
        [bc loadURLInNewWindow:URL animated:NO];

    // activate loaded tab.
    if (isFirmware6Plus && kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0 && !fromSleipnizer) {
        id tabController = [bc tabController];
        id tabExposeView = MSHookIvar<id>(tabController, "_tabExposeView");
        [tabExposeView _updateDocumentIndex];
        [tabExposeView animateAddNewTabDocument:restoredTab];

        SwitchToTab(restoredTab);
    } else if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0 && !fromSleipnizer) {
        SwitchToTab(restoredTab);
        id tabController = [bc tabController];
        [tabController _dismissTiltedTabView];
    }
}

// button click or hold interface {{{
%hook Application

%new
- (void)restoreTab
{ 
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0) {
        id tabController = [BC tabController];
        id tabExposeView = MSHookIvar<id>(tabController, "_tabExposeView");
        /*  NSLog(@"isShowing = %@", [tabExposeView isShowing] ? @"YES" : @"NO");*/
        if ([tabExposeView respondsToSelector:@selector(isShowing)] && [tabExposeView isShowing])
            [self restoreTabFromSleipnizer:NO];
        else
            [self restoreTabFromSleipnizer:YES];
    } else {
        [self restoreTabFromSleipnizer:NO];
    }
}

%new
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

    Log(@"lastObject url=%@", [[killedDocuments lastObject] URLString]);
    Log(@"killDocDict=%lu", (unsigned long)[killedDocumentsBackForwardDict count]);
    Log(@"killDoc=%lu", (unsigned long)[killedDocuments count]);

    restoringStackNumber = 1;
    LoadURLFromStackThenMoveTab([[killedDocuments lastObject] URL], fromSleipnizer);
}

%new
- (void)restoreButtonHeld:(UILongPressGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateBegan)
        return;
    if (restoringTab) {
        Alert(@"Now restoring. Please wait little.");
        return;
    }
    if (killedDocuments.count == 0)
        return;

    RestoreSheet *rs = [[RestoreSheet alloc] init];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:rs cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.actionSheetStyle = UIBarStyleBlackTranslucent;
    for (TabDocument *doc in [killedDocuments reverseObjectEnumerator])
        [sheet addButtonWithTitle:[doc title]];
    [sheet setCancelButtonIndex:[sheet addButtonWithTitle:@"Cancel"]];
    /*    [sheet showInView:[self window]];*/
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0) {
        [sheet showInView:MSHookIvar<id>(BC, "_rootView")];
    } else {
        [sheet showInView:MSHookIvar<id>(BC, "_pageView")];
    }
    [sheet release];
}

%group iOS_le_6
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
%end
// }}}

// ActionSheet delegate {{{
@implementation RestoreSheet
- (void)actionSheet:(UIActionSheet*)sheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != [sheet cancelButtonIndex]) {
        Log(@"restorering...");
        restoringStackNumber = ++buttonIndex;
        LoadURLFromStackThenMoveTab([[killedDocuments objectAtIndex:[killedDocuments count] - restoringStackNumber] URL], NO);
    }

    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0) {
        [self release];
        self = nil;
    } else {
        [self autorelease];
    }
}
@end
// }}}

// backup close tab document and update historys hook methods. {{{

static inline void SaveBackForwardHistory(TabDocument *tab)
{
    if ([tab URL] != nil) {
        if ([killedDocuments lastObject] != tab) {
            [killedDocuments addObject:tab];
            [killedDocumentsBackForwardDict addObject:[tab backForwardListDictionary]];
        }
        [button setEnabled:YES];
        [restoreButton setEnabled:YES];
        Log(@"killDocDict=%lu", (unsigned long)[killedDocumentsBackForwardDict count]);
        Log(@"killDoc=%lu", (unsigned long)[killedDocuments count]);
    }
}

%hook TabController//compatible Sleipnizer // (quick) + (go expose) + (afterShrink) // all support!
%group iOS_ge_6
- (void)closeTabDocument:(TabDocument *)tab animated:(BOOL)animated
{
    SaveBackForwardHistory(tab);
    %orig;
    if ([self respondsToSelector:@selector(_updateTiltedTabViewCloudTabs)])
        [self _updateTiltedTabViewCloudTabs];
}
%end
%end

%hook TabDocument
%group iOS_le_5
// until iOS <= 5.x.
- (void)closeTabDocument // fast than above method.
{
    SaveBackForwardHistory(self);
    %orig;
}
%end

// }}}

// restore the BackForward History! {{{
/////////////////////////////////////////////////////////////////////////////

static inline void UpdateBackForward(TabDocument *self)
{
    if (restoringTab) {
        Log(@"update if in=%@", [self backForwardListDictionary]);
        Log(@"removingCurrentBackForwardItem = YES");
        // this two is remove current backforwarditem.
        removingCurrentBackForwardItem = YES;
        if (!isFirmware6Plus)
            [self backForwardListDictionary];// magic method! must need! ... no longer necesarry on iOS 6.
        else
            restoringTab = NO; // current(loaded url) history delete timing is changed in iOS 6. So change the restoringTab set to NO timing `currentItem` to this function for iOS 6.

        [self setBackForwardListDictionary:[killedDocumentsBackForwardDict objectAtIndex:[killedDocumentsBackForwardDict count] - restoringStackNumber]];
        //Log(@"after setDict=%@", [self backForwardListDictionary]);
        [self restoreBackForwardListFromDictionary];
        //Log(@"after restore=%@", [self backForwardListDictionary]);  

        if ([self respondsToSelector:@selector(_updateBackForward)])
            [self _updateBackForward];
        //Log(@"after update=%@", [self backForwardListDictionary]);
        /*    id toolbar = MSHookIvar<id>(BC, "_buttonBar");*/
        /*    [toolbar updateButtonsAnimated:YES];*/
        if (isFirmware6Plus) {
            id loadingController = MSHookIvar<id>(self, "_loadingController");
            [loadingController _updateBackForward];
        }

        [killedDocumentsBackForwardDict removeObjectAtIndex:[killedDocumentsBackForwardDict count] - restoringStackNumber];
        [killedDocuments removeObjectAtIndex:[killedDocuments count] - restoringStackNumber];
        Log(@"removed_killDocDict=%lu", (unsigned long)[killedDocumentsBackForwardDict count]);
        Log(@"removed_killDoc=%lu", (unsigned long)[killedDocuments count]);

        TabController *tabController = [BC tabController];
        if ([tabController respondsToSelector:@selector(_updateTiltedTabViewCloudTabs)])
            [tabController _updateTiltedTabViewCloudTabs];
    }
}

// this method until iOS 5
%group iOS_le_5
- (void)_updateBackForward
{
    %orig;
    UpdateBackForward(self);
}
%end
%end

// new _updateBackForward in iOS 6!
%group iOS_ge_6
%hook WebUIBrowserLoadingController
- (void)_updateBackForward
{
    %orig;
    /*  UpdateBackForward([[[BC tabController] tabDocuments] lastObject]);*/
    /*  for (TabDocument *tab in [[BC tabController] tabDocuments]) {*/
    /*    Log(@"tab = %@, title = %@", tab, [tab title]);*/
    /*  }*/
    /*  Log(@"restoredTab = %@, title = %@", restoredTab, [restoredTab title]);*/
    UpdateBackForward(restoredTab);
}
%end
%end
// }}}

// current ( loaded url ) history delete. {{{
/////////////////////////////////////////////////////////////////////////////

%hook WebBackForwardList
- (id)currentItem
{
    Log(@"current =%@", [self dictionaryRepresentation]);
    if (removingCurrentBackForwardItem) {
        //Log(@"before removeItem=%@", [self dictionaryRepresentation]);
        if (!isFirmware6Plus) {
            [self removeItem:[self itemAtIndex:0]];
            restoringTab = NO; // set to NO timing changed since iOS6. goto UpdateBackForward function.
        }
        //Log(@"after removeItem=%@", [self dictionaryRepresentation]);
        removingCurrentBackForwardItem = NO;
        Log(@"removingCurrentBackForwardItem = NO;");
    }

    // remove loaded url history for iOS 6.
    if (isFirmware6Plus && restoringTab) {
        //Log(@"IOS6!!!! before removeItem=%@", [self dictionaryRepresentation]);
        [self removeItem:[self itemAtIndex:0]];
        //Log(@"IOS&!!!! after removeItem=%@", [self dictionaryRepresentation]);
    }
    return %orig;
}
%end
// }}}

///////////////////// Constructor
%ctor
{
    @autoreleasepool {
        static BOOL isPad = [[[UIDevice currentDevice] model] isEqualToString:@"iPad"];
        isFirmware4x = [[[UIDevice currentDevice] systemVersion] hasPrefix:@"4"];
        isFirmware5Plus = (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_5_0) ? YES : NO;
        isFirmware6Plus = (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_6_0) ? YES : NO;

        if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0) {
            dlopen("/Library/MobileSubstrate/DynamicLibraries/EnhancedTabs.dylib", RTLD_LAZY);
            Class $TabHandler = objc_getClass("TabHandler");
            hasEnhancedTabs = (class_getInstanceMethod($TabHandler, @selector(closeTabs:)) != NULL);
        }

        %init;
        if (isPad) {
            if (!isFirmware5Plus)
                %init(restoreTabForiPad);
        } else {
            if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_6_0)
                %init(iOS_le_5);
            if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0)
                %init(iOS_le_6);
            if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_6_0)
                %init(iOS_ge_6);
            if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0)
                %init(iOS_ge_7);
        }
    }
}

/* vim: set fdm=marker : */
