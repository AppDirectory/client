//
//  KBUserProfileView.m
//  Keybase
//
//  Created by Gabriel on 1/12/15.
//  Copyright (c) 2015 Gabriel Handford. All rights reserved.
//

#import "KBUserProfileView.h"

#import "KBApp.h"
#import "KBUserHeaderView.h"
#import "KBUserInfoView.h"
#import "KBProofResult.h"
#import "KBFatalErrorView.h"
#import "KBTrackView.h"
#import "KBProgressOverlayView.h"
#import "KBProveView.h"
#import "KBRPClient.h"
#import "KBKeySelectView.h"
#import "KBPGPKeyGenView.h"
#import "KBProgressView.h"
#import "KBKeyView.h"
#import "KBKeyImportView.h"

#import "KBAlertView.h"
#import "KBWorkspace.h"
#import "KBNotifications.h"
#import "KBProofView.h"
#import "KBProofRepairView.h"

@interface KBUserProfileView ()
@property KBScrollView *scrollView;
@property KBUserHeaderView *headerView;
@property KBUserInfoView *userInfoView;
@property KBTrackView *trackView;

@property NSString *username;
@property NSMutableArray *fokids;
@property NSString *trackToken;

@property (getter=isLoading) BOOL loading;
@end

@implementation KBUserProfileView

- (void)viewInit {
  [super viewInit];
  
  _headerView = [[KBUserHeaderView alloc] init];
  _userInfoView = [[KBUserInfoView alloc] init];
  _trackView = [[KBTrackView alloc] init];
  _trackView.untrackButton.targetBlock = ^{ [self untrack]; };
  YOView *contentView = [[YOView alloc] init];
  [contentView addSubview:_headerView];
  [contentView addSubview:_userInfoView];
  [contentView addSubview:_trackView];

  YOSelf yself = self;
  contentView.viewLayout = [YOLayout layoutWithLayoutBlock:^CGSize(id<YOLayout> layout, CGSize size) {
    CGFloat y = 0;
    //CGSize headerSize = [yself.headerView sizeThatFits:CGSizeMake(MIN(400, size.width) - 20, size.height)];
    //y += [layout centerWithSize:headerSize frame:CGRectMake(0, y, MIN(400, size.width), headerSize.height) view:yself.headerView].size.height;
    y += [layout sizeToFitVerticalInFrame:CGRectMake(0, y, size.width - 20, 0) view:yself.headerView].size.height;
    y += [layout sizeToFitVerticalInFrame:CGRectMake(0, y, size.width, 0) view:yself.userInfoView].size.height;
    y += [layout sizeToFitVerticalInFrame:CGRectMake(0, y, size.width, 0) view:yself.trackView].size.height;
    return CGSizeMake(size.width, y);
  }];

  _scrollView = [[KBScrollView alloc] init];
  [_scrollView setDocumentView:contentView];
  [self addSubview:_scrollView];

  self.viewLayout = [YOLayout fill:_scrollView];
}

- (void)updatePopupWindow {
  if (self.popup) {
    // If we are in a popup lets adjust our window so all the content is visible
    CGSize size = [self sizeThatFits:self.frame.size];
    [self.window setContentSize:size];
  }
}


- (void)clear {
  _username = nil;
  _fokids = nil;
  _headerView.hidden = YES;
  [_userInfoView clear];
  [_trackView clear];
  _trackView.hidden = YES;
  [self setNeedsLayout];
}

- (void)openPopupWindow {
  NSAssert(self.fromWindow, @"No window");
  [self removeFromSuperview];
  [self.fromWindow kb_addChildWindowForView:self size:CGSizeMake(400, 400) makeKey:NO];
}

- (void)registerClient:(KBRPClient *)client sessionId:(NSInteger)sessionId {
  GHWeakSelf gself = self;
  self.client = client;

  [client registerMethod:@"keybase.1.identifyUi.start" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    [self clear];

    KBRStartRequestParams *requestParams = [[KBRStartRequestParams alloc] initWithParams:params];
    gself.username = requestParams.username;
    gself.headerView.hidden = NO;
    [gself.headerView setUsername:requestParams.username];
    [gself setNeedsLayout];
    [gself updatePopupWindow];
    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.displayKey" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRDisplayKeyRequestParams *requestParams = [[KBRDisplayKeyRequestParams alloc] initWithParams:params];
    if (!gself.fokids) gself.fokids = [NSMutableArray array];
    [gself.fokids addObject:requestParams.key];
    [gself.userInfoView addKey:requestParams.key targetBlock:^(KBRIdentifyKey *key) {
      [self openKey:key];
    }];
    [gself setNeedsLayout];
    [gself updatePopupWindow];
    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.launchNetworkChecks" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRLaunchNetworkChecksRequestParams *requestParams = [[KBRLaunchNetworkChecksRequestParams alloc] initWithParams:params];
    BOOL isSelf = [[KBApp.app currentUsername] isEqual:self.username];
    [gself.userInfoView addProofs:requestParams.id.proofs editable:isSelf targetBlock:^(KBProofLabel *proofLabel) {
      if (proofLabel.proofResult.result.proofResult.status != 1) {
        [self repairProof:proofLabel.proofResult];
      } else if (proofLabel.proofResult.result.hint.humanUrl) {
        [self viewProof:proofLabel.proofResult];
      }
    }];
    [gself setNeedsLayout];
    [gself updatePopupWindow];

    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.displayCryptocurrency" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRDisplayCryptocurrencyRequestParams *requestParams = [[KBRDisplayCryptocurrencyRequestParams alloc] initWithParams:params];
    [gself.userInfoView addCryptocurrency:requestParams.c targetBlock:^(KBRCryptocurrency *cryptocurrency) {

    }];
    [gself setNeedsLayout];
    [gself updatePopupWindow];
    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.finishSocialProofCheck" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRFinishSocialProofCheckRequestParams *requestParams = [[KBRFinishSocialProofCheckRequestParams alloc] initWithParams:params];
    KBRRemoteProof *proof = requestParams.rp;
    KBRLinkCheckResult *lcr = requestParams.lcr;
    [gself.userInfoView updateProofResult:[KBProofResult proofResultForProof:proof result:lcr]];
    [gself setNeedsLayout];
    [gself updatePopupWindow];
    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.finishWebProofCheck" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRFinishWebProofCheckRequestParams *requestParams = [[KBRFinishWebProofCheckRequestParams alloc] initWithParams:params];
    KBRRemoteProof *proof = requestParams.rp;
    KBRLinkCheckResult *lcr = requestParams.lcr;
    [gself.userInfoView updateProofResult:[KBProofResult proofResultForProof:proof result:lcr]];
    [gself setNeedsLayout];
    [gself updatePopupWindow];
    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.reportLastTrack" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    // TODO Show this?
    [gself setNeedsLayout];
    [gself updatePopupWindow];
    completion(nil, nil);
  }];

  [client registerMethod:@"keybase.1.identifyUi.finishAndPrompt" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRFinishAndPromptRequestParams *requestParams = [[KBRFinishAndPromptRequestParams alloc] initWithParams:params];

    KBUserTrackStatus *trackStatus = [[KBUserTrackStatus alloc] initWithUsername:gself.username identifyOutcome:requestParams.outcome];
    [self showTrackPrompt:trackStatus completion:^(BOOL track) {
      // There is a daemon bug where keybase generates local track statement anyway
      if (track) {
        KBRFinishAndPromptRes *response = [[KBRFinishAndPromptRes alloc] init];
        response.trackRemote = YES;
        completion(nil, response);
      } else {
        completion(nil, nil);
      }
    }];
    [gself setNeedsLayout];
    [gself updatePopupWindow];
  }];

  [client registerMethod:@"keybase.1.identifyUi.finish" sessionId:sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    completion(nil, nil);
  }];
}

- (BOOL)isLoadingUsername:(NSString *)username {
  return [self.username isEqualToString:username] && _loading;
}

- (void)showTrackPrompt:(KBUserTrackStatus *)trackStatus completion:(void (^)(BOOL track))completion {
  GHWeakSelf gself = self;
  self.trackView.hidden = NO;
  [self.trackView setTrackStatus:trackStatus skipable:self.popup completion:^(BOOL track) {
    if (!track) {
      [gself showTrackAction:KBTrackActionSkipped username:trackStatus.username error:nil];
      completion(NO);
    } else {
      // How to handle errors from callback prompt
      [gself showTrackAction:KBTrackActionTracked username:trackStatus.username error:nil];
      completion(YES);
    }
  }];
  [self setNeedsLayout];

  if (self.popup) {
    if (trackStatus.status != KBTrackStatusValid) {
      [self openPopupWindow];
    } else {
      completion(NO); // No need to track
    }
  }
}

- (void)showTrackOption:(KBRIdentifyRes *)identify {
  NSAssert([identify.user.username isEqualTo:self.username], @"Mismatched users");
  self.trackToken = identify.trackToken;

  GHWeakSelf gself = self;
  KBUserTrackStatus *trackStatus = [[KBUserTrackStatus alloc] initWithUsername:identify.user.username identifyOutcome:identify.outcome];
  self.trackView.hidden = NO;
  [self.trackView setTrackStatus:trackStatus skipable:self.popup completion:^(BOOL track) {
    if (track) {
      [gself track:trackStatus.username];
    } else {
      [gself showTrackAction:KBTrackActionSkipped username:identify.user.username error:nil];
    }
  }];
}

- (void)track:(NSString *)username {
  KBRTrackRequest *request = [[KBRTrackRequest alloc] initWithClient:self.client];
  GHWeakSelf gself = self;
  [KBActivity setProgressEnabled:YES sender:self];
  [self registerClient:self.client sessionId:request.sessionId];
  [request trackWithTokenWithSessionID:request.sessionId trackToken:self.trackToken localOnly:NO approveRemote:YES completion:^(NSError *error) {
    [KBActivity setProgressEnabled:NO sender:self];
    if (error) {
      [gself showTrackAction:KBTrackActionErrored username:username error:error];
    } else {
      [gself showTrackAction:KBTrackActionTracked username:username error:nil];
    }
  }];
}

- (void)showTrackAction:(KBTrackAction)trackAction username:(NSString *)username error:(NSError *)error {
  [self.trackView setTrackAction:trackAction error:error];

  dispatch_async(dispatch_get_main_queue(), ^{
    [NSNotificationCenter.defaultCenter postNotificationName:KBTrackingListDidChangeNotification object:nil userInfo:@{@"username": username}];
  });

  if (self.popup) {
    [[self window] close];
  }
}

- (void)identify {
  [self.headerView setProgressEnabled:YES];
  _loading = YES;
  GHWeakSelf gself = self;
  KBRIdentifyRequest *identifyRequest = [[KBRIdentifyRequest alloc] initWithClient:self.client];
  [self registerClient:self.client sessionId:identifyRequest.sessionId];
  [identifyRequest identifyDefaultWithSessionID:identifyRequest.sessionId userAssertion:_username completion:^(NSError *error, KBRIdentifyRes *identifyRes) {
    [gself.headerView setProgressEnabled:NO];
    gself.loading = NO;
    if (error) {
      [KBActivity setError:error sender:self];
      return;
    }
    [self showTrackOption:identifyRes];
  }];
}

- (void)identifySelf {
  [self.headerView setProgressEnabled:YES];
  _loading = YES;
  GHWeakSelf gself = self;
  KBRIdentifyRequest *identifyRequest = [[KBRIdentifyRequest alloc] initWithClient:self.client];
  [self registerClient:self.client sessionId:identifyRequest.sessionId];
  [identifyRequest identifyDefaultWithSessionID:identifyRequest.sessionId userAssertion:_username completion:^(NSError *error, KBRIdentifyRes *identifyRes) {
    [gself.headerView setProgressEnabled:NO];
    gself.loading = NO;
    if (error) {
      [KBActivity setError:error sender:self];
      return;
    }

    if ([gself.fokids count] == 0) {
      NSAttributedString *textLabel = [KBAppearance.currentAppearance attributedString:@"Add a PGP Key" style:KBTextStyleDefault options:KBTextOptionsSelect alignment:NSLeftTextAlignment lineBreakMode:NSLineBreakByWordWrapping];
      [gself.userInfoView addHeader:nil text:textLabel targetBlock:^{ [gself addPGPKey]; }];
    }

    for (NSString *serviceName in [gself.userInfoView missingServices]) {
      NSString *label = nil;
      if ([serviceName isEqualTo:@"dns"]) label = @"Add Domain";
      else if ([serviceName isEqualTo:@"http"]) label = @"Add Website";
      else if ([serviceName isEqualTo:@"https"]) label = @"Add Website";
      else label = NSStringWithFormat(@"Connect to %@", KBNameForServiceName(serviceName));

      NSAttributedString *icon = [KBFontAwesome attributedStringForIcon:serviceName style:KBTextStyleDefault options:0 alignment:NSLeftTextAlignment lineBreakMode:NSLineBreakByClipping];
      NSAttributedString *textLabel = [KBAppearance.currentAppearance attributedString:label style:KBTextStyleDefault options:KBTextOptionsSelect alignment:NSLeftTextAlignment lineBreakMode:NSLineBreakByCharWrapping];
      [gself.userInfoView addHeader:icon text:textLabel targetBlock:^{ [gself createProofWithServiceName:serviceName]; }];
    }
    [self setNeedsLayout];
  }];
}

- (void)refresh {
  [self setUsername:_username client:self.client];
}

- (void)setUsername:(NSString *)username client:(KBRPClient *)client {
  NSParameterAssert(client);
  if ([self isLoadingUsername:username]) return;
  NSAssert(!_loading, @"In progress");

  [self clear];

  self.client = client;
  _username = username;
  _fokids = nil;

  if (!_username) return;

  BOOL isSelf = [[KBApp.app currentUsername] isEqual:username];

  [_headerView setUsername:_username];
  _headerView.hidden = NO;

  if (!isSelf) {
    [self identify];
  } else {
    [self identifySelf];
  }

  [self setNeedsLayout];
}

- (void)untrack {
  [self.headerView setProgressEnabled:YES];
  KBRTrackRequest *request = [[KBRTrackRequest alloc] initWithClient:self.client];
  GHWeakSelf gself = self;
  NSString *username = _username;
  [request untrackWithSessionID:request.sessionId theirName:username completion:^(NSError *error) {
    [self.headerView setProgressEnabled:NO];
    if (error) {
      [gself showTrackAction:KBTrackActionErrored username:username error:error];
    } else {
      [gself showTrackAction:KBTrackActionUntracked username:username error:nil];
    }
  }];
}

#pragma mark Add PGP

- (void)addPGPKey {
  KBRConfigRequest *request = [[KBRConfigRequest alloc] initWithClient:self.client];
  [request getConfigWithSessionID:request.sessionId completion:^(NSError *error, KBRConfig *config) {
    KBAlertView *alert = [[KBAlertView alloc] init];
    [alert addButtonWithTitle:@"Import Manually" tag:1];
    if (config.gpgExists) [alert addButtonWithTitle:@"Import from GPG" tag:2];
    [alert addButtonWithTitle:@"Generate New Key" tag:3];
    [alert addButtonWithTitle:@"Cancel" tag:5];

    [alert setMessageText:@"Already have a PGP key?"];
    [alert setInformativeText:@"Would you like to import a key, or generate a new one?"];
    [alert showInView:self completion:^(NSInteger tag) {
      if (tag == 2) {
        [self selectGPGKey];
      } else if (tag == 1) {
        [self importKey];
      } else if (tag == 3) {
        [self generatePGPKey];
      }
    }];
  }];
}

- (void)openKey:(KBRIdentifyKey *)key {
  KBKeyView *keyView = [[KBKeyView alloc] init];
  keyView.client = self.client;
  BOOL isSelf = [[KBApp.app currentUsername] isEqual:self.username];
  [keyView setKey:key editable:isSelf];
  keyView.cancelButton.dispatchBlock = ^(KBButton *button, dispatch_block_t completion) { [[button window] close]; completion(); };

  [self.window kb_addChildWindowForView:keyView rect:CGRectMake(0, 0, 500, 400) position:KBWindowPositionCenter title:@"Key" fixed:NO makeKey:YES];
}

- (void)generatePGPKey {
  KBProgressView *progressView = [[KBProgressView alloc] init];
  [progressView setProgressTitle:@"Generating"];
  progressView.work = ^(KBCompletion completion) {
    KBRPGPCreateUids *uids = [[KBRPGPCreateUids alloc] init];
    uids.useDefault = YES;
    KBRPgpRequest *request = [[KBRPgpRequest alloc] initWithClient:self.client];
    [request pgpKeyGenDefaultWithSessionID:request.sessionId createUids:uids completion:^(NSError *error) {
      completion(error);
      [self refresh];
    }];
  };
  [progressView openAndDoIt:(KBWindow *)self.window];
}

- (void)selectGPGKey {
  KBRPgpRequest *request = [[KBRPgpRequest alloc] initWithClient:self.client];
  [self.client registerMethod:@"keybase.1.gpgUi.selectKeyAndPushOption" sessionId:request.sessionId requestHandler:^(NSNumber *messageId, NSString *method, NSArray *params, MPRequestCompletion completion) {
    KBRSelectKeyAndPushOptionRequestParams *requestParams = [[KBRSelectKeyAndPushOptionRequestParams alloc] initWithParams:params];
    [self selectPGPKey:requestParams completion:completion];
  }];
  [request pgpSelectWithSessionID:request.sessionId fingerprintQuery:nil allowMulti:NO skipImport:NO completion:^(NSError *error) {
    [KBActivity setError:error sender:self];
    [self refresh];
  }];
}

- (void)selectPGPKey:(KBRSelectKeyAndPushOptionRequestParams *)handler completion:(MPRequestCompletion)completion {
  KBKeySelectView *selectView = [[KBKeySelectView alloc] init];
  selectView.client = self.client;

  [(KBWindow *)self.window addModalWindowForView:selectView rect:CGRectMake(0, 0, 620, 420)];

  [selectView setGPGKeys:handler.keys];
  selectView.completion = ^(id sender, id result) {
    [[sender window] close];
    completion(nil, result);
  };
}

- (void)importKey {
  KBKeyImportView *importView = [[KBKeyImportView alloc] init];
  importView.client = self.client;
  [(KBWindow *)self.window addModalWindowForView:importView rect:CGRectMake(0, 0, 620, 420)];
  importView.completion = ^(id sender, BOOL imported) {
    if (imported) [self refresh];
    [[sender window] close];
  };
}

#pragma mark Proof

- (void)viewProof:(KBProofResult *)proofResult {
  KBProofView *proofView = [[KBProofView alloc] init];
  proofView.proofResult = proofResult;
  proofView.client = self.client;
  GHWeakSelf gself = self;
  proofView.completion = ^(id sender, KBProofAction action) {
    [gself handleProofAction:action proofResult:proofResult];
    [[sender window] close];
  };
  NSString *title = KBNameForServiceName(proofResult.proof.key);
  [self.window kb_addChildWindowForView:proofView rect:CGRectMake(0, 0, 500, 200) position:KBWindowPositionCenter title:title fixed:NO makeKey:YES];
}

- (void)repairProof:(KBProofResult *)proofResult {
  KBProofRepairView *proofRepairView = [[KBProofRepairView alloc] init];
  proofRepairView.proofResult = proofResult;
  proofRepairView.client = self.client;
  GHWeakSelf gself = self;
  proofRepairView.completion = ^(id sender, KBProofAction action) {
    [gself handleProofAction:action proofResult:proofResult];
    [[sender window] close];
  };
  [self.window kb_addChildWindowForView:proofRepairView rect:CGRectMake(0, 0, 500, 200) position:KBWindowPositionCenter title:@"Proof Failed" fixed:NO makeKey:YES];
}

- (void)handleProofAction:(KBProofAction)proofAction proofResult:(KBProofResult *)proofResult {
  switch (proofAction) {
    case KBProofActionRetry: [self retryProof:proofResult]; break;
    case KBProofActionReplace: [self replaceProof:proofResult]; break;
    case KBProofActionRevoke: [self revokeProof:proofResult]; break;
    case KBProofActionOpen: [self openProof:proofResult]; break;
    case KBProofActionCancel: break;
  }
}

- (void)createProofWithServiceName:(NSString *)serviceName {
  GHWeakSelf gself = self;
  [KBProveView createProofWithServiceName:serviceName client:self.client window:(KBWindow *)self.window completion:^(id sender, BOOL success) {
    [gself refresh]; // TODO We're always reloading even if canceled
  }];
}

- (void)retryProof:(KBProofResult *)proofResult {
  NSString *sigID = proofResult.proof.sigID;
  KBRProveRequest *request = [[KBRProveRequest alloc] initWithClient:self.client];
  [KBActivity setProgressEnabled:YES sender:self];
  [request checkProofWithSessionID:request.sessionId sigID:sigID completion:^(NSError *error, KBRCheckProofStatus *checkProofStatus) {
    [KBActivity setProgressEnabled:NO sender:self];
    if ([KBActivity setError:error sender:self]) return;

    if (checkProofStatus.found) {
      [self refresh];
    } else {
      [KBActivity setError:KBMakeError(checkProofStatus.status, @"Oops, we couldn't find the proof.") sender:self];
    }
  }];
}

- (void)replaceProof:(KBProofResult *)proofResult {
  GHWeakSelf gself = self;
  [KBProveView replaceProof:proofResult client:self.client window:(KBWindow *)self.window completion:^(id sender, BOOL success) {
    [gself refresh]; // Always reload even if canceled
  }];
}

- (void)openProof:(KBProofResult *)proofResult {
  [KBWorkspace openURLString:proofResult.result.hint.humanUrl prompt:NO sender:self];
}

- (void)revokeProof:(KBProofResult *)proofResult {
  [KBAlert yesNoWithTitle:@"Quit" description:@"Are you sure you want to revoke this proof?" yes:@"Revoke" view:self completion:^(BOOL yes) {
    if (yes) [self _revokeProof:proofResult];
  }];
}

- (void)_revokeProof:(KBProofResult *)proofResult {
  NSAssert(proofResult.proof.sigID, @"No proof sigId");
  GHWeakSelf gself = self;
  [KBActivity setProgressEnabled:YES sender:self];
  KBRRevokeRequest *request = [[KBRRevokeRequest alloc] initWithClient:self.client];
  [request revokeSigsWithSessionID:request.sessionId ids:@[proofResult.proof.sigID] seqnos:nil completion:^(NSError *error) {
    [KBActivity setProgressEnabled:NO sender:self];
    [gself refresh];
  }];
}

@end

@interface KBUserProfileViewer ()
@property KBUserProfileView *view;
@end


@implementation KBUserProfileViewer

- (void)viewInit {
  [super viewInit];
  YOSelf yself = self;
  self.viewLayout = [YOLayout layoutWithLayoutBlock:^CGSize(id<YOLayout> layout, CGSize size) {
    [layout setSize:size view:yself.view options:0];
    return size;
  }];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(update:) name:KBTrackingListDidChangeNotification object:nil];
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)update:(NSNotification *)notification {
  if ([notification.userInfo[@"username"] isEqualToString:_view.username]) {
    [_view refresh];
  }
}

- (void)clear {
  [_view clear];
}

- (void)setUsername:(NSString *)username client:(KBRPClient *)client {
  if (!username) {
    [_view removeFromSuperview];
    _view = nil;
    return;
  }

  if ([_view isLoadingUsername:username]) return;

  // Check if we need  a new view
  if (!_view || [_view isLoading]) {
    [_view removeFromSuperview];
    _view = [[KBUserProfileView alloc] init];
    [self setNeedsLayout];
  }
  if (![_view superview]) [self addSubview:_view];

  [_view setUsername:username client:client];
}

@end