#import <FSSwitchDataSource.h>
#import <FSSwitchPanel.h>

#import <Preferences/Preferences.h>
#import <dlfcn.h>

@interface WirelessModemController : PSListController {
}
- (id)internetTethering:(PSSpecifier *)specifier;
- (void)setInternetTethering:(id)value specifier:(PSSpecifier *)specifier;
@end

typedef enum {
	NETRB_SVC_STATE_ON = 1023,
	NETRB_SVC_STATE_OFF = 1022,
} NETRB_SVC_STATE;

@interface MISManager : NSObject
+ (MISManager *)sharedManager;
- (void)setState:(NETRB_SVC_STATE)state;
- (void)getState:(NETRB_SVC_STATE *)outState andReason:(int *)reason;
@end

static WirelessModemController *controller;
static MISManager *manager;
static PSSpecifier *specifier;
static NSInteger insideSwitch;

%hook UIAlertView

- (void)show
{
	if (insideSwitch) {
		// Make sure we're suppressing the right alert view
		if ([[self buttons] count] == 2) {
			id<UIAlertViewDelegate> delegate = [self delegate];
			if ([delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) {
				[delegate alertView:self clickedButtonAtIndex:0];
				return;
			}
		}
	}
	%orig();
}

%end

%hook WirelessModemController

- (void)_btPowerChangedHandler:(NSNotification *)notification
{
	// Just eat it!
}

%end

@interface HotspotSwitch : NSObject <FSSwitchDataSource>
@end

%hook SBTelephonyManager

- (void)noteWirelessModemChanged
{
	%orig();
	[[FSSwitchPanel sharedPanel] stateDidChangeForSwitchIdentifier:[NSBundle bundleForClass:[HotspotSwitch class]].bundleIdentifier];
}

%end

@implementation HotspotSwitch

- (FSSwitchState)stateForSwitchIdentifier:(NSString *)switchIdentifier
{
	if (manager) {
		NETRB_SVC_STATE state = 0;
		[manager getState:&state andReason:NULL];
		switch (state) {
			case NETRB_SVC_STATE_ON:
				return FSSwitchStateOn;
			case NETRB_SVC_STATE_OFF:
				return FSSwitchStateOff;
			default:
				return FSSwitchStateIndeterminate;
		}
	}
	return [[controller internetTethering:specifier] boolValue];
}

- (void)applyState:(FSSwitchState)newState forSwitchIdentifier:(NSString *)switchIdentifier
{
	if (newState == FSSwitchStateIndeterminate)
		return;
	if (manager) {
		[manager setState:(newState == FSSwitchStateOn) ? NETRB_SVC_STATE_ON : NETRB_SVC_STATE_OFF];
		return;
	}
	insideSwitch++;
	[controller setInternetTethering:[NSNumber numberWithBool:newState] specifier:specifier];
	insideSwitch--;
}

@end

%ctor {
	// Load WirelessModemSettings
	dlopen("/System/Library/PreferenceBundles/WirelessModemSettings.bundle/WirelessModemSettings", RTLD_LAZY);
	%init();
	if ((manager = [objc_getClass("MISManager") sharedManager]))
		return;
	// Create root controller
	PSRootController *rootController = [[PSRootController alloc] initWithTitle:@"Preferences" identifier:@"com.apple.Preferences"];
	// Create controller
	controller = [[%c(WirelessModemController) alloc] initForContentSize:(CGSize){ 0.0f, 0.0f }];
	[controller setRootController:rootController];
	[controller setParentController:rootController];
	// Create Specifier
	specifier = [[PSSpecifier preferenceSpecifierNamed:@"Tethering" target:controller set:@selector(setInternetTethering:specifier:) get:@selector(internetTethering:) detail:Nil cell:PSSwitchCell edit:Nil] retain];
}
