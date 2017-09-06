//
//  IPAPatchEntry.m
//  IPAPatch
//
//  Created by wutian on 2017/3/17.
//  Copyright © 2017年 Weibo. All rights reserved.
//

#import "IPAPatchEntry.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

/**
 *  插件功能
 */
static int const kCloseRedEnvPlugin = 0;
static int const kOpenRedEnvPlugin = 1;
static int const kCloseRedEnvPluginForMyself = 2;
static int const kCloseRedEnvPluginForMyselfFromChatroom = 3;
//0：关闭红包插件
//1：打开红包插件
//2: 不抢自己的红包
//3: 不抢群里自己发的红包
static int HBPliginType = 1;
static NSMutableDictionary *params;
static id logicMgr;

#define SAVESETTINGS(key, value) { \
NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES); \
NSString *docDir = [paths objectAtIndex:0]; \
if (!docDir){ return;} \
NSMutableDictionary *dict = [NSMutableDictionary dictionary]; \
NSString *path = [docDir stringByAppendingPathComponent:@"HBPluginSettings.txt"]; \
[dict setObject:value forKey:key]; \
[dict writeToFile:path atomically:YES]; \
}

@implementation IPAPatchEntry

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self exchangeSEL:@selector(m7StepCount) SEL:@selector(______count) class:NSClassFromString(@"WCDeviceStepObject")];
        
        [self exchangeSEL:@selector(AsyncOnAddMsg:MsgWrap:) SEL:@selector(________AsyncOnAddMsg:MsgWrap:) class:NSClassFromString(@"CMessageMgr")];
        NSString *identifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
        [self exchangeSEL:@selector(OnWCToHongbaoCommonResponse:Request:) SEL:@selector(______OnWCToHongbaoCommonResponse:Request:) class:NSClassFromString(@"WCRedEnvelopesLogicMgr")];
        
        [self for_example_showAlert];
    });
}

+ (void)exchangeSEL:(SEL)origin SEL:(SEL)swizzle class:(Class)class {
    Method method = class_getInstanceMethod([self class], swizzle);
    class_addMethod(class, swizzle, method_getImplementation(method), method_getTypeEncoding(method));
    
    Method originMethod = class_getInstanceMethod(class, origin);
    Method swizzleMethod = class_getInstanceMethod(class, swizzle);
    
    BOOL add = class_addMethod(class, origin, method_getImplementation(swizzleMethod), method_getTypeEncoding(swizzleMethod));
    if (add) {
        class_replaceMethod(class, swizzle, method_getImplementation(originMethod), method_getTypeEncoding(originMethod));
    }else {
        method_exchangeImplementations(originMethod, swizzleMethod);
    }
}

//=================================================================
//                           微信抢红包
//=================================================================
#pragma mark - 微信抢红包
- (void)______OnWCToHongbaoCommonResponse:(id)hongbaoCommonResponse Request:(id)request {
    [self ______OnWCToHongbaoCommonResponse:hongbaoCommonResponse Request:request];
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:(NSData *)[[hongbaoCommonResponse performSelector:@selector(retText)] performSelector:@selector(buffer)] options:kNilOptions error:nil];
    
    if ([msg isKindOfClass:[NSDictionary class]]) {
        if (msg[@"timingIdentifier"]) {
            //自动抢红包
            [params setObject:msg[@"timingIdentifier"] forKey:@"timingIdentifier"];
            
            ((void (*)(id, SEL, NSMutableDictionary*))objc_msgSend)(logicMgr, @selector(OpenRedEnvelopesRequest:), params);
        }
    }
}

- (void)________AsyncOnAddMsg:(id)arg1 MsgWrap:(id)arg2 {
    [self ________AsyncOnAddMsg:arg1 MsgWrap:arg2];
    
    Ivar uiMessageTypeIvar = class_getInstanceVariable(objc_getClass("CMessageWrap"), "m_uiMessageType");
    ptrdiff_t offset = ivar_getOffset(uiMessageTypeIvar);
    unsigned char *stuffBytes = (unsigned char *)(__bridge void *)arg2;
    NSUInteger m_uiMessageType = * ((NSUInteger *)(stuffBytes + offset));
    
    Ivar nsFromUsrIvar = class_getInstanceVariable(objc_getClass("CMessageWrap"), "m_nsFromUsr");
    id m_nsFromUsr = object_getIvar(arg2, nsFromUsrIvar);
    
    Ivar nsContentIvar = class_getInstanceVariable(objc_getClass("CMessageWrap"), "m_nsContent");
    id m_nsContent = object_getIvar(arg2, nsContentIvar);
    
    switch(m_uiMessageType) {
        case 1:
        {
            //普通消息
            //红包插件功能
            //0：关闭红包插件
            //1：打开红包插件
            //2: 不抢自己的红包
            //3: 不抢群里自己发的红包
            //微信的服务中心
            Method methodMMServiceCenter = class_getClassMethod(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            IMP impMMSC = method_getImplementation(methodMMServiceCenter);
//            ((int (*)(id, SEL))(void *)objc_msgSend)((id)p, sel_registerName("age"));
            id MMServiceCenter = ((id (*)(Class,SEL))(impMMSC))(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            //通讯录管理器
            id contactManager = ((id (*)(id, SEL, Class))objc_msgSend)(MMServiceCenter, @selector(getService:),objc_getClass("CContactMgr"));
            id selfContact = ((id (*)(id, SEL))(void *)objc_msgSend)((id)contactManager, @selector(getSelfContact));
            
            Ivar nsUsrNameIvar = class_getInstanceVariable([selfContact class], "m_nsUsrName");
            id m_nsUsrName = object_getIvar(selfContact, nsUsrNameIvar);
            BOOL isMesasgeFromMe = NO;
            if ([m_nsFromUsr isEqualToString:m_nsUsrName]) {
                //发给自己的消息
                isMesasgeFromMe = YES;
            }
            
            if (isMesasgeFromMe)
            {
                if ([m_nsContent rangeOfString:@"打开红包插件"].location != NSNotFound)
                {
                    HBPliginType = kOpenRedEnvPlugin;
                }
                else if ([m_nsContent rangeOfString:@"关闭红包插件"].location != NSNotFound)
                {
                    HBPliginType = kCloseRedEnvPlugin;
                }
                else if ([m_nsContent rangeOfString:@"关闭抢自己红包"].location != NSNotFound)
                {
                    HBPliginType = kCloseRedEnvPluginForMyself;
                }
                else if ([m_nsContent rangeOfString:@"关闭抢自己群红包"].location != NSNotFound)
                {
                    HBPliginType = kCloseRedEnvPluginForMyselfFromChatroom;
                }
                
                SAVESETTINGS(@"HBPliginType", [NSNumber numberWithInt:HBPliginType]);
            }
        }
            break;
        case 49: {
            // 49=红包
            
            //微信的服务中心
            Method methodMMServiceCenter = class_getClassMethod(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            IMP impMMSC = method_getImplementation(methodMMServiceCenter);
            id MMServiceCenter = ((id (*)(Class, SEL))impMMSC)(objc_getClass("MMServiceCenter"), @selector(defaultCenter));
            //红包控制器
            logicMgr = ((id (*)(id, SEL, Class))objc_msgSend)(MMServiceCenter, @selector(getService:),objc_getClass("WCRedEnvelopesLogicMgr"));
            
            //通讯录管理器
            id contactManager = ((id (*)(id, SEL, Class))objc_msgSend)(MMServiceCenter, @selector(getService:),objc_getClass("CContactMgr"));
            
            Method methodGetSelfContact = class_getInstanceMethod(objc_getClass("CContactMgr"), @selector(getSelfContact));
            IMP impGS = method_getImplementation(methodGetSelfContact);
            id selfContact = ((id (*)(id, SEL))impGS)(contactManager, @selector(getSelfContact));
            
            Ivar nsUsrNameIvar = class_getInstanceVariable([selfContact class], "m_nsUsrName");
            id m_nsUsrName = object_getIvar(selfContact, nsUsrNameIvar);
            BOOL isMesasgeFromMe = NO;
            BOOL isChatroom = NO;
            if ([m_nsFromUsr isEqualToString:m_nsUsrName]) {
                isMesasgeFromMe = YES;
            }
            if ([m_nsFromUsr rangeOfString:@"@chatroom"].location != NSNotFound)
            {
                isChatroom = YES;
            }
            if (isMesasgeFromMe && kCloseRedEnvPluginForMyself == HBPliginType && !isChatroom) {
                //不抢自己的红包
                break;
            }
            else if(isMesasgeFromMe && kCloseRedEnvPluginForMyselfFromChatroom == HBPliginType && isChatroom)
            {
                //不抢群里自己的红包
                break;
            }
            
            if ([m_nsContent rangeOfString:@"wxpay://"].location != NSNotFound)
            {
                NSString *nativeUrl = m_nsContent;
                NSRange rangeStart = [m_nsContent rangeOfString:@"wxpay://c2cbizmessagehandler/hongbao"];
                if (rangeStart.location != NSNotFound)
                {
                    NSUInteger locationStart = rangeStart.location;
                    nativeUrl = [nativeUrl substringFromIndex:locationStart];
                }
                
                NSRange rangeEnd = [nativeUrl rangeOfString:@"]]"];
                if (rangeEnd.location != NSNotFound)
                {
                    NSUInteger locationEnd = rangeEnd.location;
                    nativeUrl = [nativeUrl substringToIndex:locationEnd];
                }
                
                NSString *naUrl = [nativeUrl substringFromIndex:[@"wxpay://c2cbizmessagehandler/hongbao/receivehongbao?" length]];
                
                NSArray *parameterPairs =[naUrl componentsSeparatedByString:@"&"];
                
                NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithCapacity:[parameterPairs count]];
                for (NSString *currentPair in parameterPairs) {
                    NSRange range = [currentPair rangeOfString:@"="];
                    if(range.location == NSNotFound)
                        continue;
                    NSString *key = [currentPair substringToIndex:range.location];
                    NSString *value =[currentPair substringFromIndex:range.location + 1];
                    [parameters setObject:value forKey:key];
                }
                
                //红包参数
                params = [@{} mutableCopy];
                
                [params setObject:parameters[@"msgtype"]?:@"null" forKey:@"msgType"];
                [params setObject:parameters[@"sendid"]?:@"null" forKey:@"sendId"];
                [params setObject:parameters[@"channelid"]?:@"null" forKey:@"channelId"];
                
                //            ((int (*)(id, SEL))(void *)objc_msgSend)((id)p, sel_registerName("age"));
                id getContactDisplayName = ((id (*)(id, SEL))(void *)objc_msgSend)((id)selfContact, @selector(getContactDisplayName));
                
                id m_nsHeadImgUrl = ((id (*)(id, SEL))(void *)objc_msgSend)((id)selfContact, @selector(m_nsHeadImgUrl));
                
                [params setObject:getContactDisplayName forKey:@"nickName"];
                [params setObject:m_nsHeadImgUrl forKey:@"headImg"];
                [params setObject:[NSString stringWithFormat:@"%@", nativeUrl]?:@"null" forKey:@"nativeUrl"];
                [params setObject:m_nsFromUsr?:@"null" forKey:@"sessionUserName"];
                  
                if (kCloseRedEnvPlugin != HBPliginType) {
                    ((void (*)(id, SEL, NSMutableDictionary*))objc_msgSend)(logicMgr, @selector(ReceiverQueryRedEnvelopesRequest:),params);
                    
//                    //自动抢红包
//                    ((void (*)(id, SEL, NSMutableDictionary*))objc_msgSend)(logicMgr, @selector(OpenRedEnvelopesRequest:), params);
                }
                return;
            }
            
            break;
        }
        default:
            break;
    }
}

//=================================================================
//                           修改微信运动步数
//=================================================================
#pragma mark - 修改微信运动步数
- (unsigned int)______count {
    unsigned int count = [self ______count];
    NSLog(@"%d",count);
    return 21315;
}

//=================================================================
//                           调试
//=================================================================
#pragma mark - 调试
+ (void)for_example_showAlert
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class Test = NSClassFromString(@"UIDebuggingInformationOverlay");
        
        if ([(id)[Test class] respondsToSelector:@selector(prepareDebuggingOverlay)]) {
            [[Test class] performSelectorOnMainThread:@selector(prepareDebuggingOverlay) withObject:nil waitUntilDone:YES];
        }
    });
}

- (void)prepareDebuggingOverlay {
    NSLog(@"%s",__FUNCTION__);
}

@end
