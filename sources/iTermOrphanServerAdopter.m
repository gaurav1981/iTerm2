//
//  iTermOrphanServerAdopter.m
//  iTerm2
//
//  Created by George Nachman on 6/7/15.
//
//

#import "iTermOrphanServerAdopter.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermFileDescriptorSocketPath.h"
#import "PseudoTerminal.h"

@implementation iTermOrphanServerAdopter {
    NSArray *_pathsToOrphanedServerSockets;
    PseudoTerminal *_window;  // weak
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (![iTermAdvancedSettingsModel runJobsInServers]) {
        return nil;
    }
    self = [super init];
    if (self) {
        _pathsToOrphanedServerSockets = [[self findOrphanServers] retain];
    }
    return self;
}

- (void)dealloc {
    [_pathsToOrphanedServerSockets release];
    [super dealloc];
}

- (NSArray *)findOrphanServers {
    NSMutableArray *array = [NSMutableArray array];
    NSString *dir = [NSString stringWithUTF8String:iTermFileDescriptorDirectory()];
    for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
        NSString *prefix = [NSString stringWithUTF8String:iTermFileDescriptorSocketNamePrefix];
        if ([filename hasPrefix:prefix]) {
            [array addObject:filename];
        }
    }
    return array;
}

- (void)openWindowWithOrphans {
    for (NSString *path in _pathsToOrphanedServerSockets) {
        [self adoptOrphanWithPath:path];
    }
    _window = nil;
}

- (void)adoptOrphanWithPath:(NSString *)filename {
    // TODO: This needs to be able to time out if a server is wedged, which happened somehow.
    NSLog(@"Try to connect to server at %@", filename);
    pid_t pid = iTermFileDescriptorProcessIdFromPath(filename.UTF8String);
    if (pid < 0) {
        NSLog(@"Invalid pid in filename %@", filename);
        return;
    }

    FileDescriptorClientResult result = FileDescriptorClientRun(pid);
    if (result.ok) {
        NSLog(@"Restore it");
        if (_window) {
            [self openOrphanedSession:result inWindow:_window];
        } else {
            PTYSession *session = [self openOrphanedSession:result inWindow:nil];
            _window = [[iTermController sharedInstance] terminalWithSession:session];
        }
    }
}

- (PTYSession *)openOrphanedSession:(FileDescriptorClientResult)result
                           inWindow:(PseudoTerminal *)desiredWindow {
    assert([iTermAdvancedSettingsModel runJobsInServers]);
    Profile *defaultProfile = [[ProfileModel sharedInstance] defaultBookmark];
    PTYSession *aSession =
    [[iTermController sharedInstance] launchBookmark:nil
                                          inTerminal:desiredWindow
                                             withURL:nil
                                            isHotkey:NO
                                             makeKey:NO
                                             command:nil
                                               block:^PTYSession *(PseudoTerminal *term) {
                                                   FileDescriptorClientResult theResult = result;
                                                   term.disablePromptForSubstitutions = YES;
                                                   return [term createSessionWithProfile:defaultProfile
                                                                                 withURL:nil
                                                                           forObjectType:iTermWindowObject
                                                              fileDescriptorClientResult:&theResult];
                                               }];
    [aSession showOrphanAnnouncement];
    return aSession;
}

#pragma mark - Properties

- (BOOL)haveOrphanServers {
    return _pathsToOrphanedServerSockets.count > 0;
}

@end
