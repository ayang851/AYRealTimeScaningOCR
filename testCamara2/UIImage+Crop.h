//
//  UIImage+Crop.h
//  testCamara2
//
//  Created by ayang on 2018/3/14.
//  Copyright © 2018年 ayang. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (Crop)

-(UIImage*)getSubImage:(CGRect)rect;

@end
