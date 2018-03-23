//
//  ViewController.m
//  testCamara
//
//  Created by ayang on 2018/3/12.
//  Copyright © 2018年 ayang. All rights reserved.
//

/*
 * chi_sim.traineddata下载地址：https://github.com/tesseract-ocr/tessdata/blob/bf82613055ebc6e63d9e3b438a5c234bfd638c93/chi_sim.traineddata
 *
 *
 *
 */

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "UIImage+Crop.h"
#import <TesseractOCR/TesseractOCR.h>





//分辨率 与相机分辨率对应：AVCaptureSessionPreset1920x1080
#define kResolutionWidth   1080.0
#define kResolutionHeight  1920.0
// 屏幕尺寸
#define SCREEN_HEIGHT [[UIScreen mainScreen] bounds].size.height
#define NavHeight 64
#define SCREEN_WIDTH [[UIScreen mainScreen] bounds].size.width
#define DeveiceScale [UIScreen mainScreen].scale

#define CropWidth SCREEN_WIDTH - 40
#define CropHeight 60

//焦距倍数
#define kFocalScale 2.0

@interface ViewController ()<AVCaptureMetadataOutputObjectsDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>


{
    
    BOOL _isFoucePixel;//是否开启对焦
    CGRect zoom;
    CGRect cropPresetZoom;
    G8Tesseract *tesseract;
    BOOL isreging;
    //    BOOL _isChangedType;//切换识别类型
    float _isIOS8AndFoucePixelLensPosition;//相位聚焦下镜头位置
}
//@property (strong, nonatomic) avaut

@property (nonatomic, strong) AVCaptureSession * session;
@property (nonatomic, strong) AVCaptureDevice * device;


@property (strong, nonatomic) AVCaptureDeviceInput *captureInput;
@property (strong, nonatomic) AVCaptureStillImageOutput *captureOutput;

@property (strong, nonatomic) AVCaptureConnection *videoConnection;

@property (strong, nonatomic) AVCaptureVideoPreviewLayer *preview;
/** 扫描支持的编码格式的数组 */
@property (nonatomic, strong) NSMutableArray *metadataObjectTypes;

//文通ocr相关
@property (assign, nonatomic) BOOL adjustingFocus;//是否正在对焦


@property (strong, nonatomic) CALayer *shapeLayer;


@property (strong, nonatomic) UIImageView *imageV;


@property (strong, nonatomic) UILabel *contextLabel;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initialize];
    self.preview.position = self.view.center;
    [self.preview setAffineTransform:CGAffineTransformMakeScale(kFocalScale, kFocalScale)];
    [self.view.layer addSublayer:self.shapeLayer];
    [self setfousMod];
    
    
    zoom =  [self.view.layer convertRect:self.shapeLayer.frame toLayer:self.preview];
    float xZoom =  kResolutionWidth/self.preview.bounds.size.width;
    float yZoom =  kResolutionHeight/self.preview.bounds.size.height;
    cropPresetZoom = CGRectMake(zoom.origin.x * xZoom, zoom.origin.y  * yZoom, zoom.size.width  * xZoom, zoom.size.height  * yZoom);
//    [self.shapeLayer setAffineTransform:CGAffineTransformMakeScale(1.0/kFocalScale, 1.0/kFocalScale)];
//    self.shapeLayer.position = CGPointMake(self.preview.position.x, self.preview.position.y - 100 );
    [self.view addSubview:self.imageV];
    [self.view addSubview:self.contextLabel];
    //判断对焦方式
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        AVCaptureDeviceFormat *deviceFormat = self.device.activeFormat;
        if (deviceFormat.autoFocusSystem == AVCaptureAutoFocusSystemPhaseDetection){
            _isFoucePixel = YES;
        }
    }
    
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    AVCaptureDevice*camDevice =[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    int flags = NSKeyValueObservingOptionNew;
    //注册通知
    [camDevice addObserver:self forKeyPath:@"adjustingFocus" options:flags context:nil];
    if (_isFoucePixel) {
        [camDevice addObserver:self forKeyPath:@"lensPosition" options:flags context:nil];
    }
    [self.session startRunning];
}

- (void) viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    //移除聚焦监听
    AVCaptureDevice*camDevice =[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [camDevice removeObserver:self forKeyPath:@"adjustingFocus"];
    if (_isFoucePixel) {
        [camDevice removeObserver:self forKeyPath:@"lensPosition"];
    }
    [self.session stopRunning];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    
}

#pragma mark - 初始化识别核心
//初始化相机
- (void) initialize{
    //判断摄像头授权
//    NSString *mediaType = AVMediaTypeVideo;
//    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    //1.创建会话层
    self.session = [[AVCaptureSession alloc] init];
    //设置图片品质，此分辨率为最佳识别分辨率，建议不要改动
    [self.session setSessionPreset:AVCaptureSessionPreset1920x1080];
    
    //2.创建、配置输入设备
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices){
        if (device.position == AVCaptureDevicePositionBack){
            self.captureInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
            self.device = device;
        }
    }
    [self.session addInput:self.captureInput];
    
    //创建、配置预览输出设备
    AVCaptureVideoDataOutput *captureOutput = [[AVCaptureVideoDataOutput alloc] init];
    captureOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t queue;
    queue = dispatch_queue_create("cameraQueue", NULL);
    [captureOutput setSampleBufferDelegate:self queue:queue];
    
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    [captureOutput setVideoSettings:videoSettings];
    [self.session addOutput:captureOutput];
    
    //3.创建、配置输出
    self.captureOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG,AVVideoCodecKey,nil];
    [self.captureOutput setHighResolutionStillImageOutputEnabled:YES];
    [self.captureOutput setOutputSettings:outputSettings];
    [self.session addOutput:self.captureOutput];
    
    
    
    //设置预览
    self.preview = [AVCaptureVideoPreviewLayer layerWithSession: self.session];
    self.preview.frame = CGRectMake(0, 0,SCREEN_WIDTH,SCREEN_HEIGHT);
    self.preview.contentsGravity = kCAGravityResizeAspect;
    self.preview.borderWidth = 1.0;
    self.preview.borderColor = [UIColor greenColor].CGColor;
    self.preview.videoGravity = kCAGravityResizeAspect;
    //    self.preview.backgroundColor = [UIColor redColor].CGColor;
    [self.view.layer addSublayer:self.preview];
    
    
    //5.设置视频流和预览图层方向
    for (AVCaptureConnection *connection in captureOutput.connections) {
        for (AVCaptureInputPort *port in [connection inputPorts]) {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                self.videoConnection = connection;
                break;
            }
        }
        if (self.videoConnection) { break; }
    }
    self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [self.videoConnection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
    
    //判断对焦方式
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        AVCaptureDeviceFormat *deviceFormat = self.device.activeFormat;
        if (deviceFormat.autoFocusSystem == AVCaptureAutoFocusSystemPhaseDetection){
            _isFoucePixel = YES;
        }
    }
    
    
    
    
}
-(CALayer *)shapeLayer{

    if (!_shapeLayer) {
        _shapeLayer = [[CALayer alloc]init];
        _shapeLayer.frame = CGRectMake(20, 50, CropWidth,  CropHeight);
        _shapeLayer.borderColor = [UIColor redColor].CGColor;
        _shapeLayer.borderWidth = 1.f;
        _shapeLayer.backgroundColor = [UIColor clearColor].CGColor;
    }
    return _shapeLayer;
}


//从摄像头缓冲区获取图像
#pragma mark - AVCaptureSession delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection{
    //获取当前帧数据
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    /*Get information about the image*/
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    /*Create a CGImageRef from the CVImageBufferRef*/
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef newContext = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    CGImageRef newImage = CGBitmapContextCreateImage(newContext);
    CGImageRef newImage2 = CGImageCreateWithImageInRect(newImage, cropPresetZoom);
    CGContextRelease(newContext);
    CGImageRelease(newImage);
    UIImage* zoomedImage = [[UIImage alloc] initWithCGImage:newImage2];
    CGImageRelease(newImage2);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    [self gcdreg:zoomedImage];
   
}

-(UIImageView *)imageV{

    if (!_imageV) {
        _imageV = [[UIImageView alloc]initWithFrame:CGRectMake(0, 500, self.shapeLayer.bounds.size.width , self.shapeLayer.bounds.size.height)];
        _imageV.contentMode = UIViewContentModeScaleToFill;
        _imageV.center = CGPointMake(SCREEN_WIDTH/2.0, 400);
        _imageV.layer.borderColor = [UIColor orangeColor].CGColor;
        _imageV.layer.borderWidth = 1.0;
    }
    return _imageV;
}
                   

- (void)setfousMod{

    NSError *error = nil;
    if ([self.device lockForConfiguration:&error]) {
        CGPoint center = CGPointMake((cropPresetZoom.origin.x + cropPresetZoom.size.width/2.0)/kResolutionWidth, (cropPresetZoom.origin.y + cropPresetZoom.size.height/2.0)/kResolutionHeight);
        //对焦模式和对焦点
        if ([self.device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [self.device setFocusPointOfInterest:center];
            [self.device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        //曝光模式和曝光点
        if ([self.device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [self.device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }

        
//           self.device.
//        [self.device isviede]
//        光学防抖
//        if ([self.device.activeFormat isVideoStabilizationModeSupported:AVCaptureVideoStabilizationModeAuto]) {
//            [self.device.activeFormat set];
//        }
        
        [self.device unlockForConfiguration];
    }
}
-(UILabel *)contextLabel{
    if(!_contextLabel){
        _contextLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, SCREEN_HEIGHT - 150, SCREEN_WIDTH, 150)];
        _contextLabel.backgroundColor = [UIColor blueColor];
        _contextLabel.numberOfLines = 0;
    }
    return _contextLabel;
}


- (void)gcdreg:(UIImage *)timage {
    // 创建串行队列
    // 串行队列的特点：队列中的任务必须按顺序执行。
//    dispatch_queue_t queue = dispatch_que
//    dispatch_queue_
    
    if (isreging || self.adjustingFocus) {
        return;
    }
    isreging = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!tesseract) {
                tesseract = [[G8Tesseract alloc]initWithLanguage:@"chi_sim"];
                tesseract.engineMode = G8OCREngineModeTesseractOnly;
                tesseract.pageSegmentationMode = G8PageSegmentationModeSingleLine;
//                tesseract.charWhitelist = @"0123456789"; 
            }
            UIImage *image = timage.g8_blackAndWhite;
            tesseract.image = image;
            self.imageV.image = image;
            BOOL b = [tesseract recognize];
            if(b){
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.contextLabel.text = tesseract.recognizedText;
//                    NSLog(@"识别结果：%@",tesseract.recognizedText);
                    isreging = NO;
                });
            }else{
                dispatch_async(dispatch_get_main_queue(), ^{
//                    NSLog(@"识别失败");
                    isreging = NO;
                });
            }
            
            
        });
}


//监听对焦
-(void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    
    if([keyPath isEqualToString:@"adjustingFocus"]){
        self.adjustingFocus = [[change objectForKey:NSKeyValueChangeNewKey] isEqualToNumber:[NSNumber numberWithInt:1]];
        NSLog(@"adjustingFocus = %@",change);
    }
    if([keyPath isEqualToString:@"lensPosition"]){
        _isIOS8AndFoucePixelLensPosition = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
    }
}
@end
