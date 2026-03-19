#import "Manager.h"

@implementation SCIDownloadManager

- (instancetype)initWithDelegate:(id<SCIDownloadDelegateProtocol>)downloadDelegate {
    self = [super init];
    
    if (self) {
        self.delegate = downloadDelegate;
    }

    return self;
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension {
    // Default to mp4 for video if no other reasonable extension is provided
    self.fileExtension = [fileExtension length] >= 2 ? fileExtension : @"mp4";

    // ── Fast path: URL is already a local file (e.g. Instagram's AVPlayer cache) ──
    if ([url isFileURL]) {
        NSLog(@"[SCInsta] Download: File URL detected — copying from cache directly");
        [self.delegate downloadDidStart];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *dst = [self moveFileToCacheDir:url copyInstead:YES];
            if (dst) {
                [self.delegate downloadDidFinishWithFileURL:dst];
            } else {
                NSError *err = [NSError errorWithDomain:@"com.socuul.scinsta"
                                                   code:1
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to copy cached file"}];
                [self.delegate downloadDidFinishWithError:err];
            }
        });
        return;
    }

    // ── Normal path: download from network ──
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:nil];
    self.task = [self.session downloadTaskWithURL:url];
    [self.task resume];
    [self.delegate downloadDidStart];
}

- (void)cancelDownload {
    [self.task cancel];
    [self.delegate downloadDidCancel];
}

// URLSession methods
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    NSLog(@"Task wrote %lld bytes of %lld bytes", bytesWritten, totalBytesExpectedToWrite);
    
    float progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;

    [self.delegate downloadDidProgress:progress];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    // Move downloaded temp file to cache directory
    NSURL *finalLocation = [self moveFileToCacheDir:location copyInstead:NO];
    if (finalLocation) {
        [self.delegate downloadDidFinishWithFileURL:finalLocation];
    } else {
        NSError *err = [NSError errorWithDomain:@"com.socuul.scinsta"
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to move downloaded file"}];
        [self.delegate downloadDidFinishWithError:err];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSLog(@"Task completed with error: %@", error);
    
    [self.delegate downloadDidFinishWithError:error];
}

// Move or copy a file into the cache directory.
// copyInstead:YES = copy (for cached file:// URLs), NO = move (for downloaded temp files)
- (NSURL *)moveFileToCacheDir:(NSURL *)oldPath copyInstead:(BOOL)copyInstead {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Derive extension from source path if not already set sensibly
    NSString *srcExt = oldPath.pathExtension;
    NSString *ext = (self.fileExtension.length >= 2) ? self.fileExtension
                  : (srcExt.length >= 2)             ? srcExt
                  : @"mp4";

    NSString *cacheDirectoryPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *newPath = [[NSURL fileURLWithPath:cacheDirectoryPath]
                      URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",
                                                   NSUUID.UUID.UUIDString, ext]];

    NSLog(@"[SCInsta] Download Handler: %@ file from: %@ to: %@",
          copyInstead ? @"Copying" : @"Moving",
          oldPath.absoluteString, newPath.absoluteString);

    NSError *fileError;
    if (copyInstead) {
        [fileManager copyItemAtURL:oldPath toURL:newPath error:&fileError];
    } else {
        [fileManager moveItemAtURL:oldPath toURL:newPath error:&fileError];
    }

    if (fileError) {
        NSLog(@"[SCInsta] Download Handler: Error while %@ file: %@ — %@",
              copyInstead ? @"copying" : @"moving",
              oldPath.absoluteString, fileError);
        return nil;
    }

    return newPath;
}

@end