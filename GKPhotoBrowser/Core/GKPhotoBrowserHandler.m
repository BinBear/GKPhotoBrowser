//
//  GKPhotoBrowserHandler.m
//  GKPhotoBrowser
//
//  Created by QuintGao on 2023/3/2.
//

#import "GKPhotoBrowserHandler.h"
#import "GKPhotoBrowser.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation GKPhotoBrowserHandler

- (instancetype)init {
    if (self = [super init]) {
        [self initValue];
    }
    return self;
}

- (void)initValue {
    // 原始状态栏样式
    self.originStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    
    // 状态栏外观处理
    NSDictionary *infoDict = [NSBundle mainBundle].infoDictionary;
    BOOL hasKey = [infoDict.allKeys containsObject:@"UIViewControllerBasedStatusBarAppearance"];
    BOOL appearance = [[infoDict objectForKey:@"UIViewControllerBasedStatusBarAppearance"] boolValue];
    self.statusBarAppearance = (hasKey && appearance) || !hasKey;
}

- (void)showFromVC:(UIViewController *)vc {
    if (self.browser.showStyle == GKPhotoBrowserShowStylePush) {
        UIImage *image = [self getCaptureWithView:vc.view.window];
        self.captureImage = image;
        [vc.navigationController pushViewController:self.browser animated:YES];
    }else {
        UIViewController *presentVC = self.browser;
        if (self.browser.isAddNavigationController) {
            presentVC = [[UINavigationController alloc] initWithRootViewController:self.browser];
        }
        
        presentVC.modalPresentationCapturesStatusBarAppearance = YES;
        presentVC.modalPresentationStyle = UIModalPresentationCustom;
        presentVC.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        [vc presentViewController:presentVC animated:NO completion:nil];
    }
}

#pragma mark - BrowserShow
- (void)browserShow {
    switch (self.browser.showStyle) {
        case GKPhotoBrowserShowStyleNone:
            [self browserNoneShow];
            break;
        case GKPhotoBrowserShowStylePush:
            [self browserPushShow];
            break;
        case GKPhotoBrowserShowStyleZoom:{
            [self browserZoomShow];
        }
            break;
        default:
            break;
    }
}

- (void)browserNoneShow {
    self.browser.view.alpha = 0;
    [self browserChangeAlpha:1];
    [UIView animateWithDuration:self.browser.animDuration animations:^{
        self.browser.view.alpha = 1.0;
    }completion:^(BOOL finished) {
        self.isShow = YES;
        [self.browser browserFirstAppear];
    }];
}

- (void)browserPushShow {
    self.browser.containerView.backgroundColor = self.browser.bgColor ? : [UIColor blackColor];
    self.isShow = YES;
    [self.browser browserFirstAppear];
}

- (void)browserZoomShow {
    GKPhotoView *photoView = self.browser.curPhotoView;
    GKPhoto *photo = self.browser.curPhoto;
    
    CGRect endRect = CGRectZero;
    if (photoView.imageView.image) {
        endRect = photoView.imageView.frame;
    }else {
        if (CGRectEqualToRect(photo.sourceFrame, CGRectZero)) {
            endRect = photoView.imageView.frame;
        }else {
            CGFloat w = GKScreenW;
            // bug fixed：#43 CALayer position contains NaN: [nan nan]
            CGFloat h = (photo.sourceFrame.size.width == 0) ? GKScreenH : (w * photo.sourceFrame.size.height / photo.sourceFrame.size.width);
            CGFloat x = 0;
            CGFloat y = (GKScreenH - h) / 2;
            endRect = CGRectMake(x, y, w, h);
        }
    }
    
    CGRect sourceRect = photo.sourceFrame;
    
    if (CGRectEqualToRect(sourceRect, CGRectZero)) {
        float systemVersion = [UIDevice currentDevice].systemVersion.floatValue;
        if (systemVersion >= 8.0 && systemVersion < 9.0) {
            sourceRect = [photo.sourceImageView.superview convertRect:photo.sourceImageView.frame toCoordinateSpace:photoView];
        }else {
            sourceRect = [photo.sourceImageView.superview convertRect:photo.sourceImageView.frame toView:photoView];
        }
    }
    
    photoView.imageView.frame = sourceRect;
    [photoView updateFrame];
    
    [UIView animateWithDuration:self.browser.animDuration animations:^{
        photoView.imageView.frame = endRect;
        [photoView updateFrame];
        [self browserChangeAlpha:1];
    }completion:^(BOOL finished) {
        self.isShow = YES;
        [self.browser browserFirstAppear];
    }];
}

#pragma mark - BrowserDismiss
- (void)browserDismiss {
    GKPhotoView *photoView = self.browser.curPhotoView;
    photoView.isLayoutSubViews = YES;
    
    if (!self.browser.isFollowSystemRotation) {
        // 状态栏恢复到竖屏
        if (@available(iOS 13.0, *)) {} else {
            [[UIApplication sharedApplication] setStatusBarOrientation:UIInterfaceOrientationPortrait animated:NO];
        }
    }
    
    if (self.browser.showStyle == GKPhotoBrowserShowStylePush) {
        [self.browser removeRotationObserver];
        self.browser.photoScrollView.clipsToBounds = YES;
        [self.browser.navigationController popViewControllerAnimated:YES];
    }else {
        // 显示状态栏
        self.browser.isStatusBarShow = YES;
        
        // 防止返回时跳动
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self recoverAnimation];
        });
    }
}

// 恢复动画，如果是横屏先恢复到竖屏再消失
- (void)recoverAnimation {
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    if (!self.browser.isFollowSystemRotation && self.browser.supportedInterfaceOrientations == UIInterfaceOrientationMaskPortrait && UIDeviceOrientationIsLandscape(orientation)) {
        [UIView animateWithDuration:self.browser.animDuration animations:^{
            // 旋转view
            self.browser.contentView.transform = CGAffineTransformIdentity;
            
            CGFloat height = MAX(screenBounds.size.width, screenBounds.size.height);
            
            if (self.browser.isAdaptiveSafeArea) {
                height -= (kSafeTopSpace + kSafeBottomSpace);
            }
            // 设置frame
            self.browser.contentView.bounds = CGRectMake(0, 0, MIN(screenBounds.size.width, screenBounds.size.height), height);
            self.browser.contentView.center = self.browser.view.center;
            
            [self.browser.view setNeedsLayout];
            [self.browser.view layoutIfNeeded];
            [self.browser layoutSubviews];
        }completion:^(BOOL finished) {
            [self browserZoomDismiss];
        }];
    }else {
        [self browserZoomDismiss];
    }
}

- (void)browserZoomDismiss {
    GKPhotoView *photoView = self.browser.curPhotoView;
    if (!photoView) return;
    
    // 超出裁剪
    photoView.imageView.clipsToBounds = YES;
    
    GKPhoto *photo = photoView.photo;
    
    CGRect sourceRect = photo.sourceFrame;
    
    if (CGRectEqualToRect(sourceRect, CGRectZero)) {
        if (photo.sourceImageView == nil) {
            [UIView animateWithDuration:self.browser.animDuration animations:^{
                photoView.imageView.alpha = 0;
                [self browserChangeAlpha:0];
            }completion:^(BOOL finished) {
                [self dismissAnimated:self.browser.hideStyle == GKPhotoBrowserHideStyleZoomSlide];
            }];
            return;
        }
        
        if (self.browser.isHideSourceView) {
            photo.sourceImageView.alpha = 0;
        }
        
        float systemVersion = [UIDevice currentDevice].systemVersion.floatValue;
        if (systemVersion >= 8.0 && systemVersion < 9.0) {
            sourceRect = [photo.sourceImageView.superview convertRect:photo.sourceImageView.frame toCoordinateSpace:photoView];
        }else {
            sourceRect = [photo.sourceImageView.superview convertRect:photo.sourceImageView.frame toView:photoView];
        }
    }else {
        if (self.browser.isHideSourceView && photo.sourceImageView) {
            photo.sourceImageView.alpha = 0;
        }
    }
    
    if (photoView.scrollView.zoomScale > 1.0f) {
        [photoView.scrollView setZoomScale:1.0f animated:NO];
    }
    
    if (photo.sourceImageView) {
        photoView.imageView.image = photo.sourceImageView.image;
    }
    
    // Fix bug：解决长图点击隐藏时可能出现的闪动bug
    UIViewContentMode mode = photo.sourceImageView ? photo.sourceImageView.contentMode : UIViewContentModeScaleAspectFill;
    
    photoView.imageView.contentMode = mode;
    sourceRect.origin.x -= photoView.scrollView.contentOffset.x;
    sourceRect.origin.y += photoView.scrollView.contentOffset.y;
    
    [UIView animateWithDuration:self.browser.animDuration animations:^{
        photoView.imageView.frame = sourceRect;
        [photoView updateFrame];
        [self browserChangeAlpha:0];
    }completion:^(BOOL finished) {
        [self dismissAnimated:self.browser.hideStyle == GKPhotoBrowserHideStyleZoomSlide];
    }];
}

- (void)browserSlideDismiss:(CGPoint)point {
    GKPhotoView *photoView = self.browser.curPhotoView;
    if (!photoView) return;
    
    BOOL throwToTop = point.y < 0;
    CGFloat toTranslationY = 0;
    if (throwToTop) {
        toTranslationY = - photoView.superview.frame.size.height;
    }else {
        toTranslationY = photoView.superview.frame.size.height;
    }
    
    [UIView animateWithDuration:self.browser.animDuration animations:^{
        photoView.imageView.transform = CGAffineTransformMakeTranslation(0, toTranslationY);
        [self browserChangeAlpha:0];
    }completion:^(BOOL finished) {
        [self dismissAnimated:self.browser.hideStyle == GKPhotoBrowserHideStyleZoomSlide];
    }];
}

- (void)dismissAnimated:(BOOL)animated {
    GKPhoto *photo = self.browser.curPhotoView.photo;
    
    if (animated && self.browser.showStyle != GKPhotoBrowserShowStylePush) {
        [UIView animateWithDuration:self.browser.animDuration animations:^{
            photo.sourceImageView.alpha = 1.0;
        }];
    }else {
        photo.sourceImageView.alpha = 1.0;
    }
    
    if (!self.browser.isFollowSystemRotation) {
        if (@available(iOS 13.0, *)) {} else {
            [[UIApplication sharedApplication] setStatusBarOrientation:UIInterfaceOrientationPortrait animated:NO];
        }
    }
    
    // 移除屏幕旋转监听
    [self.browser removeRotationObserver];
    
    if (!self.statusBarAppearance) {
        [[UIApplication sharedApplication] setStatusBarStyle:self.originStatusBarStyle];
    }
    if (self.browser.showStyle == GKPhotoBrowserShowStylePush) {
        [self.browser.navigationController popViewControllerAnimated:NO];
    }else {
        [self.browser dismissViewControllerAnimated:NO completion:nil];
    }
    
    if ([self.browser.delegate respondsToSelector:@selector(photoBrowser:panEndedWithIndex:willDisappear:)]) {
        [self.browser.delegate photoBrowser:self.browser panEndedWithIndex:self.browser.currentIndex willDisappear:YES];
    }
}

- (void)browserChangeAlpha:(CGFloat)alpha {
    UIColor *bgColor = self.browser.bgColor ?: UIColor.blackColor;
    
    self.browser.containerView.backgroundColor = [bgColor colorWithAlphaComponent:alpha];
    for (UIView *view in self.browser.coverViews) {
        view.alpha = alpha;
    }
}

- (UIImage *)getCaptureWithView:(UIView *)view {
    if (!view) return nil;
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.opaque, 0);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end

#pragma clang diagnostic pop
