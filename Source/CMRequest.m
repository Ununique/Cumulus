//
//  CMRequest.m
//  Cumulus
//
//  Created by John Clayton on 7/23/11.
//  Copyright 2011 Fivesquare Software, LLC. All rights reserved.
//

/*
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 
 * 3. Neither the name of Fivesquare Software nor the names of its contributors may
 *    be used to endorse or promote products derived from this software without
 *    specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE ICONFACTORY BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "CMRequest.h"
#import "CMRequest+Protected.h"

#import "Cumulus.h"



@implementation CMRequest

+ (NSOperationQueue *) delegateQueue {
	static NSOperationQueue *delegateQueue = nil;
	@synchronized(self) {
		if (nil == delegateQueue) {
			delegateQueue = [NSOperationQueue new];
		}
	}
	return delegateQueue;
}


static NSUInteger requestCount = 0;
+ (void) incrementRequestCount {
	@synchronized(@"CMRequest.requestCount") {
		requestCount++;
#if TARGET_OS_IPHONE
		if (requestCount > 0) {
			[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
		}
#endif	
	}
}

+ (void) decrementRequestCount {
	@synchronized(@"CMRequest.requestCount") {
		requestCount--;
#if TARGET_OS_IPHONE
		if (requestCount < 1) {
			[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
		}
#endif
	}	
}

// ========================================================================== //

#pragma mark - Properties



// Public


#pragma mark - -Request State


@synthesize started=_started;
@synthesize finished=_finished;
@synthesize canceled=_canceled;
@synthesize startedAt = _startedAt;
@synthesize endedAt = _endedAt;

@dynamic elapsed;
- (NSTimeInterval) elapsed {
	return [self.endedAt timeIntervalSinceDate:self.startedAt];
}

@dynamic completed;
- (BOOL) didComplete {
	// A streamed file most likely, but either way we don't know the length, assume it's complete
	if (self.responseInternal.expectedContentLength == NSURLResponseUnknownLength) {
		return YES;
	}
	// - A range request is complete if the length of the range was returned
	// - A non-range request is complete if the expected content length was returned
	// #responseInternal.contentLength captures both of these cases
	return self.responseInternal.expectedContentLength == self.receivedContentLength;
}



#pragma mark - -Lifecycle


@synthesize didSendDataBlock=_didSendDataBlock;
@synthesize didReceiveDataBlock=_didReceiveDataBlock;
@synthesize postProcessorBlock=_resultProcessor;
@synthesize abortBlock=_abortBlock;
@synthesize completionBlock=_completionBlock;


#pragma mark - -Content Encoding/Decoding

@synthesize payloadEncoder=_payloadEncoder;
@synthesize responseDecoder=_responseDecoder;


#pragma mark - -Configuration

@synthesize identifier = _identifier;
@synthesize headers=_headers;
@synthesize timeout=_timeout;
@synthesize cachePolicy=_cachePolicy;
@synthesize authProviders=_authProviders;
@synthesize maxAuthRetries=_maxAuthRequests;
@synthesize payload=_payload;
@synthesize range = _range;

@dynamic URL;
- (NSURL *) URL {
	return _originalURLRequest.URL;
}


#pragma mark - -Execution Context


@synthesize URLRequest=_URLRequest;
@synthesize URLResponse=_URLResponse;
@synthesize bodyContentLength=_bodyContentLength;
@synthesize sentContentLength=_sentContentLength;
@synthesize expectedContentLength=_expectedContentLength;
@synthesize receivedContentLength=_receivedContentLength;
@synthesize data=_data;
@synthesize response = _response;
@synthesize result=_result;
@synthesize responseBody=_responseBody;
@synthesize error=_error;


@dynamic progressReceivedInfo;
- (CMProgressInfo *) progressReceivedInfo {
	CMProgressInfo *progressReceivedInfo = [CMProgressInfo new];
	progressReceivedInfo.request = self;
	progressReceivedInfo.URL = [self.URLRequest URL];
	float progress = 0;
	if (self.expectedContentLength > 0) {
		progress = (float)self.receivedContentLength / (float)self.expectedContentLength;
		progressReceivedInfo.progress = @(progress);
	}
	else {
		progressReceivedInfo.progress = @(0);
	}
	progressReceivedInfo.chunkSize = @(self.lastChunkSize);
	return progressReceivedInfo;
}

@dynamic progressSentInfo;
- (CMProgressInfo *) progressSentInfo {
	CMProgressInfo *progressSentInfo = [CMProgressInfo new];
	progressSentInfo.request = self;
	progressSentInfo.URL = [self.URLRequest URL];
	float progress = 0;
	if (self.bodyContentLength > 0) {
		progress = self.sentContentLength / self.bodyContentLength;
		progressSentInfo.progress = [NSNumber numberWithFloat:progress];
	}
	else {
		progressSentInfo.progress = @(0);
	}
	return progressSentInfo;
}


// Private

@synthesize connectionFinished=_connectionFinished;
@synthesize connection=_connection;
@synthesize originalURLRequest=_originalURLRequest;
@synthesize timeoutTimer=_timeoutTimer;
@synthesize requestConfigured = _requestConfigured;

@dynamic fileExtension;
- (NSString *) fileExtension {
	return [self.URLRequest.URL pathExtension];
}

@dynamic canStart;
- (BOOL) canStart {
	return (NO == self.started && NO == self.finished/* && NO == self.wasCanceled*/);
}

@dynamic canCancel;
- (BOOL) canCancel {
	return (/*YES == self.isStarted && */NO == self.isFinished && NO == self.wasCanceled);
}

@dynamic canAbort;
- (BOOL) canAbort {
	return (NO == self.started && NO == self.finished && NO == self.wasCanceled);
}

@dynamic cacheIdentifier;
- (id) cacheIdentifier {
	NSMutableString *identifier = [NSMutableString stringWithString:self.URL.absoluteString];
	if (self.range.location != kCFNotFound) {
		[identifier appendFormat:@", bytes=%lld-%lld",self.range.location,CMContentRangeLastByte(self.range)];
	}
	return identifier;
}

@synthesize responseInternal = _responseInternal;
- (CMResponse *) responseInternal {
	if (nil == _responseInternal) {
		_responseInternal = [[CMResponse alloc] initWithRequest:self];
	}
	return _responseInternal;
}


// Overrides

- (NSURLRequest *) URLRequest {
	if (_URLRequest == nil) {
		_URLRequest = [_originalURLRequest mutableCopy];
		[self configureURLRequest:_URLRequest];
	}
	return _URLRequest;
}

- (NSMutableDictionary *) headers {
	if (_headers == nil) {
		_headers = [NSMutableDictionary new];
	}
	// Once the request exists, we defer to it for the current headers
	if (self.requestIsConfigured) {
		[_headers removeAllObjects];
		[_headers addEntriesFromDictionary:[_URLRequest allHTTPHeaderFields]];
	}
	return _headers;
}

@dynamic acceptHeader;
- (NSString *) acceptHeader {
	return [self.headers objectForKey:kCumulusHTTPHeaderAccept];
}

@dynamic contentTypeHeader;
- (NSString *) contentTypeHeader {
	return [self.headers objectForKey:kCumulusHTTPHeaderContentType];
}

- (NSMutableArray *) authProviders {
	if (nil == _authProviders) {
		_authProviders = [NSMutableArray new];
	}
	return _authProviders;
}

- (NSMutableData *) data {
    if (_data == nil) {
        _data = [NSMutableData new];
    }
    return _data;
}

- (id<CMCoder>) payloadEncoder {
	NSString *contentType = @"Not set";
    if (_payloadEncoder == nil) {
		// First, check for obvious conversions of payload by class and file extension
		_payloadEncoder = [CMCoder coderForObject:_payload];
		
		if (_payloadEncoder == nil) {
			_payloadEncoder = [CMCoder coderForFileExtension:self.fileExtension];
		}
		
		contentType = [_URLRequest valueForHTTPHeaderField:kCumulusHTTPHeaderContentType];

        if (nil == _payloadEncoder) { // we have an non-literal object type, figure out encoding based on content type
            if (contentType && contentType.length > 0) {
                _payloadEncoder = [CMCoder coderForMimeType:contentType];
            }
        }
        
    }
	NSAssert2(_payloadEncoder != nil,  @"Unable to convert payload to HTTPBody using payload.class: %@, Content-Type: %@. Make sure you are using a compatible object type or file extension, or have set an appropriate Content-Type.", NSStringFromClass([_payload class]), contentType);
    return _payloadEncoder;
}

- (id<CMCoder>) responseDecoder {
    if (_responseDecoder == nil) {
        NSString *contentType = [[_URLResponse allHeaderFields] valueForKey:kCumulusHTTPHeaderContentType];
        if (contentType.length > 0) { // First, let's try content type, because the server is telling us what it sent
            _responseDecoder = [CMCoder coderForMimeType:contentType];
        }
        if (_responseDecoder == nil) { 
            // If we didn't get a decoder from content type, we will try and build a decoder based on what we were expecting
			
			_responseDecoder = [CMCoder coderForFileExtension:self.fileExtension];
			
			if (_responseDecoder == nil) {
				NSString *accepts = [_URLRequest valueForHTTPHeaderField:kCumulusHTTPHeaderAccept];
				if (accepts && accepts.length > 0) {
					_responseDecoder = [CMCoder coderForMimeType:accepts];
				}
			}
			
        }
        if (_responseDecoder == nil) { // We will essentially just pass set the NSData as the result and downstream users will have to figure out what to do with it
            _responseDecoder = [CMIdentityCoder new];
        }
    }
    return _responseDecoder;
}

@dynamic queryDictionary;
- (NSDictionary *) queryDictionary {
    NSMutableDictionary *queryDictionary = [NSMutableDictionary new];
    NSString *queryString = [[self.URLRequest URL] query];
    if (queryString) {
        NSArray *paramPairs = [queryString componentsSeparatedByString:@"&"];
        [paramPairs enumerateObjectsUsingBlock:^(NSString *pair, NSUInteger idx, BOOL *stop) {
            NSArray *params = [pair componentsSeparatedByString:@"="];
            if (params.count == 2) {
                id key = params[0];
                id value = params[1];
                [queryDictionary setObject:value forKey:key];
            }
        }];
    }
    return queryDictionary;
}


// ========================================================================== //

#pragma mark - Object

- (void)dealloc {
//    [self removeObserver:self forKeyPath:@"scope"];
}

- (id) initWithURLRequest:(NSURLRequest*)URLRequest {
    self = [super init];
	NSAssert(URLRequest != nil, @"URLRequest cannot be nil!");
	if (nil == URLRequest) {
		self = nil;
	}
    if (self) {
		self.originalURLRequest = URLRequest;
		self.cachePolicy = NSURLRequestUseProtocolCachePolicy;
		self.maxAuthRetries = 1;
		self.range = (CMContentRange){ kCFNotFound , 0, 0 };
    }
    
    return self;
}

- (NSString *) description {
	NSURLRequest *request = nil == _URLRequest ? _originalURLRequest : _URLRequest;
	NSString *stateString;
	if (self.wasCanceled) {
		stateString = @"canceled";
	}
	else if (self.isFinished) {
		stateString = @"finished";
	}
	else if (self.isStarted) {
		stateString = @"running";
	}
	else {
		stateString = @"waiting";
	}
	return [NSString stringWithFormat:@"%@(identifier: '%@', state: %@) : %@ %@",[super description],_identifier,stateString,[request HTTPMethod],[request description]];
}


// ========================================================================== //

#pragma mark - Control


- (void) start {
	NSAssert(NO == self.started, @"Attempting to start a request that has already been started or has finished");
	if (NO == self.canStart) {
		return;
	}
	
	// If a request was asked to cancel before it was completely set up, we will handle that now and bail
	if (self.wasCanceled) {
		[self handleConnectionFinished];
		return;
	}
	
	[self handleConnectionWillStart];
	
    self.started = YES;
	self.startedAt = [NSDate date];

	self.connection = [[NSURLConnection alloc] initWithRequest:self.URLRequest delegate:self startImmediately:NO];
    [self.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
//	[self.connection setDelegateQueue:[[self class] delegateQueue]];
//	[self.connection setDelegateQueue:[NSOperationQueue mainQueue]];
//	_queue = [NSOperationQueue new];
//	[self.connection setDelegateQueue:_queue];
    [self.connection start];
	RCLog(@"%@", self);

	[self handleConnectionDidSendData];
	[self handleConnectionDidReceiveData];
	

	if (self.timeout > 0) {
		NSTimer *timeoutTimer = [NSTimer timerWithTimeInterval:self.timeout target:self selector:@selector(timeoutFired:) userInfo:nil repeats:NO];
		[[NSRunLoop mainRunLoop] addTimer:timeoutTimer forMode:NSDefaultRunLoopMode];		
		self.timeoutTimer = timeoutTimer;
	}
}

- (void) startWithCompletionBlock:(CMCompletionBlock)block {
    self.completionBlock = block;
    [self start];
}

- (void) cancel {
    if (NO == self.canCancel) {
		RCLog(@"Attempting to cancel a request that has already been canceled or has finished ");
        return;
    }
    self.canceled = YES;
	if (self.started) {
		//	[self.connection cancel];
		// strangely, *NOT* calling this on the main thread will cause other calls to dispatch on the main thread (like to completion block) to deadlock, freakish, something about the connection needing to be canceled on the same runloop it was canceled on?
		[self.connection performSelectorOnMainThread:@selector(cancel) withObject:nil waitUntilDone:NO];
		[self handleConnectionFinished];
	}
}


- (void) abort {
	if (NO == self.canAbort) {
		RCLog(@"Attempting to abort a request that has already been started, canceled or finished ");
		return;
	}
    if (self.abortBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.abortBlock(self);
        });
    }
}

- (void) abortWithBlock:(CMAbortBlock)abortBlock {
	self.abortBlock = abortBlock;
	[self abort];
}

- (void) timeoutFired:(NSTimer *)timer {
	[self.timeoutTimer invalidate];
	self.timeoutTimer = nil;
    if (nil == self.URLResponse) {
		NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
							  [NSString stringWithFormat:@"Request did not receive a response before specified timeout (%f)",self.timeout], NSLocalizedDescriptionKey
							  , self.URLRequest.URL, NSURLErrorFailingURLErrorKey
							  , nil];
		NSError *timeoutError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:info];
		self.error = timeoutError;
        [self cancel];
    }
}



// ========================================================================== //

#pragma mark - Connection Event Handlers


- (void) handleConnectionWillStart {
	// Generally used by subclasses to effect request customization
}

- (void) handleConnectionDidReceiveResponse {
	// Generally used by subclasses to make adjustments based on initial information from the server
}

- (void) handleConnectionDidReceiveData {
	if (self.canceled || self.connectionFinished) {
		return;
	}
	if (self.didReceiveDataBlock) {
		CMProgressInfo *progressInfo = self.progressReceivedInfo;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.didReceiveDataBlock(progressInfo);
		});
	}
}

- (void) handleConnectionDidSendData {
	if (self.canceled || self.connectionFinished) {
		return;
	}
	if (self.didSendDataBlock) {
		CMProgressInfo *progressInfo = self.progressSentInfo;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			self.didSendDataBlock(progressInfo);
		});
	}
}

- (void) handleConnectionFinished {
    if (self.connectionFinished) {
        return;
    }
	self.connectionFinished = YES;
	
	// Make sure processing the results doesn't stop us from calling our completion block
	@try {
		dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
		dispatch_sync(q, ^{
			[self postProcessResponse:self.responseInternal];
		});
	}
	@catch (NSException *exception) {
		self.error = [NSError errorWithDomain:kCumulusErrorDomain code:kCumulusErrorCodeErrorProcessingResponse userInfo:[exception userInfo]];
	}
	@finally {
		if (self.completionBlock) {
			dispatch_async(dispatch_get_main_queue(), ^{
				self.completionBlock(self.responseInternal);
				self.responseInternal = nil;
			});
		}
		else {
			self.responseInternal = nil;
		}
		self.timeoutTimer = nil;
		self.finished = YES;
		self.endedAt = [NSDate date];
	}
}


// ========================================================================== //

#pragma mark - URLRequest/Response Helpers


- (void) configureURLRequest:(NSMutableURLRequest *)URLRequest {
	[URLRequest setAllHTTPHeaderFields:self.headers];
	
	for (id<CMAuthProvider> authProvider in self.authProviders) {
		[authProvider authorizeRequest:URLRequest];
	}
	
	URLRequest.cachePolicy = self.cachePolicy;
    
	// if there is a payload, encode it
	if (self.payload) {
		URLRequest.HTTPBody = [self.payloadEncoder encodeObject:self.payload];
	}
	
	if (self.timeout > 0) {
		URLRequest.timeoutInterval = self.timeout;
	}
	
	if (self.range.location != kCFNotFound) {
		[URLRequest setValue:[NSString stringWithFormat:@"bytes=%lld-%lld",self.range.location,CMContentRangeLastByte(self.range)] forHTTPHeaderField:kCumulusHTTPHeaderRange];
	}
	
	self.requestConfigured = YES;
}

- (void) postProcessResponse:(CMResponse *)response {
    
	// if there was a response body, decode it
    if (self.data.length) {
        NSString *responseString = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
		self.responseBody = responseString;
        
		if (self.responseDecoder) {
			self.result = [self.responseDecoder decodeData:self.data];
		}
		
		if (self.postProcessorBlock) {
			self.result = self.postProcessorBlock(response, self.result);
		}
    }
}

- (NSString *) mimeTypeForFileAtPath:(NSString *)filePath {
	CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[filePath pathExtension], NULL);
    NSString *MIMEType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
	
    if (nil == MIMEType) {
        MIMEType = @"text/plain";
    }
	return MIMEType;
}


// ========================================================================== //

#pragma mark - NSURLConnectionDelegate


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	self.error = error;
	[self handleConnectionFinished];
}

// NSURLConnection.h says this is still valid, docs say it's deprecated, in any event it seems to never get called anymore ...
- (BOOL)connectionShouldUseCredentialStorage:(NSURLConnection *)connection {
	return NO;
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
	NSString *authMethod = [[challenge protectionSpace] authenticationMethod];
	
	id<CMAuthProvider> providerForMethod = nil;
	for (id<CMAuthProvider> provider in self.authProviders) {
		if ([provider.providedAuthenticationMethod isEqualToString:authMethod]) {
			providerForMethod = provider;
			break;
		}
	}

	if (providerForMethod) {		
		NSURLCredential *credential = [providerForMethod credentialForAuthenticationChallenge:challenge];	
		if (credential) {
            if ([challenge previousFailureCount] < self.maxAuthRetries) {
                [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
            } else {
                [[challenge sender] cancelAuthenticationChallenge:challenge];
            }
		} else {
			[[challenge sender] cancelAuthenticationChallenge:challenge];
		}
	} else {
		[[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}


// ========================================================================== //

#pragma mark - NSURLConnectionDataDelegate


- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response {
	if (response && self.authProviders.count > 0) {
		NSMutableURLRequest *authorizedRequest = [request mutableCopy];
		for (id<CMAuthProvider> authProvider in self.authProviders) {
			[authProvider authorizeRequest:authorizedRequest];
		}
		return authorizedRequest;
	}
	return request;
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
	self.sentContentLength = totalBytesWritten;
	self.bodyContentLength = totalBytesExpectedToWrite;
	
	[self handleConnectionDidSendData];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	self.URLResponse = (NSHTTPURLResponse *)response;
//	RCLog(@"response.headers: %@",[self.URLResponse allHeaderFields]);
//	self.expectedContentLength = [response expectedContentLength]; // fails when there is no content length header, often in a range request this is true
	// Works for simple requests as well as range requests
	self.expectedContentLength = self.responseInternal.expectedContentLength;
	[self handleConnectionDidReceiveResponse];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	[self.data appendData:data];

	NSUInteger dataLength = [data length];
	self.receivedContentLength += dataLength;
	self.lastChunkSize = dataLength;
	[self handleConnectionDidReceiveData];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	[self handleConnectionFinished];
}





@end
