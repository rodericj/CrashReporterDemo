/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
 * Copyright (c) 2009 Andreas Linde & Kent Sutherland. All rights reserved.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "crashReportSender.h"

@interface CrashReportSender(private)
- (void) searchCrashLogFile:(NSString *)path;
- (BOOL) hasPendingCrashReport;
- (void) returnToMainApplication;
@end

@interface CrashReportSenderUI(private)
- (void) askCrashReportDetails;
- (void) endCrashReporter;
@end

@implementation CrashReportSender


+ (CrashReportSender *)sharedCrashReportSender
{
	static CrashReportSender *crashReportSender = nil;
	
	if (crashReportSender == nil) {
		crashReportSender = [[CrashReportSender alloc] init];
	}
	
	return crashReportSender;
}


- (id) init
{
	self = [super init];
	
	if ( self != nil)
	{
		_serverResult = CrashReportStatusFailureDatabaseNotAvailable;

		_delegate = nil;
		_companyName = @"";
		_crashReportSenderUI = nil;
		_submissionURL = nil;
		
		NSArray* libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, TRUE);
		// Snow Leopard is having the log files in another location
		[self searchCrashLogFile:[[libraryDirectories lastObject] stringByAppendingPathComponent:@"Logs/DiagnosticReports"]];
		if (_crashFile == nil) {
			[self searchCrashLogFile:[[libraryDirectories lastObject] stringByAppendingPathComponent:@"Logs/CrashReporter"]];
		}		
	}
	return self;
}


- (void)dealloc
{
	_companyName = nil;
	_delegate = nil;
	_submissionURL = nil;
	[_crashReportSenderUI release];
	
	[super dealloc];
}


- (void) searchCrashLogFile:(NSString *)path
{
	NSFileManager* fman = [NSFileManager defaultManager];
	
    NSError* error;
	NSMutableArray* filesWithModificationDate = [NSMutableArray array];
	NSArray* crashLogFiles = [fman contentsOfDirectoryAtPath:path error:&error];
	NSEnumerator* filesEnumerator = [crashLogFiles objectEnumerator];
	NSString* crashFile;
	while((crashFile = [filesEnumerator nextObject]))
	{
		NSString* crashLogPath = [path stringByAppendingPathComponent:crashFile];
		NSDate* modDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:crashLogPath error:&error] fileModificationDate];
		[filesWithModificationDate addObject:[NSDictionary dictionaryWithObjectsAndKeys:crashFile,@"name",crashLogPath,@"path",modDate,@"modDate",nil]];
	}
	
	NSSortDescriptor* dateSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"modDate" ascending:YES];
	NSArray* sortedFiles = [filesWithModificationDate sortedArrayUsingDescriptors:[NSArray arrayWithObject:dateSortDescriptor]];
	
	NSPredicate* filterPredicate = [NSPredicate predicateWithFormat:@"name BEGINSWITH %@", [self applicationName]];
	NSArray* filteredFiles = [sortedFiles filteredArrayUsingPredicate:filterPredicate];
	
	_crashFile = [[filteredFiles valueForKeyPath:@"path"] lastObject];	
}


#pragma mark GetCrashData


- (BOOL) hasPendingCrashReport
{
	BOOL returnValue = NO;
	NSError* error;
    
	NSDate *lastCrashDate = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.lastCrashDate"];
	
	NSDate *crashLogModificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:_crashFile error:&error] fileModificationDate];
	
	if (lastCrashDate && crashLogModificationDate && ([crashLogModificationDate compare: lastCrashDate] == NSOrderedDescending))
	{
		returnValue = YES;
	}
	
	[[NSUserDefaults standardUserDefaults] setValue: crashLogModificationDate
											 forKey: @"CrashReportSender.lastCrashDate"];
	
	return returnValue;
}


- (void) sendCrashReportToURL:(NSURL *)submissionURL delegate:(id)delegate companyName:(NSString *)companyName
{
    _delegate = delegate;
    
    if ([self hasPendingCrashReport])
    {
        _submissionURL = [submissionURL copy];
        _companyName = companyName;
        
        _crashReportSenderUI = [[CrashReportSenderUI alloc] init:self crashFile:_crashFile companyName:_companyName applicationName:[self applicationName]];
        [_crashReportSenderUI askCrashReportDetails];
    } else {
        [self returnToMainApplication];
    }
}


- (void) returnToMainApplication
{
	if ( _delegate != nil && [_delegate respondsToSelector:@selector(showMainApplicationWindow)])
		[_delegate showMainApplicationWindow];
}



- (void) cancelReport
{
    [self returnToMainApplication];
}


- (void) sendReport:(NSString *)xml
{
    [self returnToMainApplication];
	
	NSTimer *_submitTimer;
	_submitTimer = [NSTimer scheduledTimerWithTimeInterval:0.0 target:self selector:@selector(postXML:) userInfo:xml repeats:NO];	 
}

- (void) postXML:(NSTimer *) timer
{
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_submissionURL];
	NSString *boundary = @"----FOO";
	
	[request setTimeoutInterval: 15];
	[request setHTTPMethod:@"POST"];
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data, boundary=%@", boundary];
	[request setValue:contentType forHTTPHeaderField:@"Content-type"];
	
	NSMutableData *postBody =  [NSMutableData data];
	[postBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	[postBody appendData:[@"Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[postBody appendData:[[timer userInfo] dataUsingEncoding:NSUTF8StringEncoding]];
	[postBody appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	[request setHTTPBody:postBody];
	
	_serverResult = CrashReportStatusUnknown;
	_statusCode = 200;
	
	NSHTTPURLResponse *response = nil;
	NSError *error = nil;
	
	NSData *responseData = nil;
	responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	_statusCode = [response statusCode];

	if (responseData != nil)
	{
		if (_statusCode >= 200 && _statusCode < 400)
		{
			NSXMLParser *parser = [[NSXMLParser alloc] initWithData:responseData];
			// Set self as the delegate of the parser so that it will receive the parser delegate methods callbacks.
			[parser setDelegate:self];
			// Depending on the XML document you're parsing, you may want to enable these features of NSXMLParser.
			[parser setShouldProcessNamespaces:NO];
			[parser setShouldReportNamespacePrefixes:NO];
			[parser setShouldResolveExternalEntities:NO];
			
			[parser parse];
			
			[parser release];
		}
		
// TODO: The following line causes the app to crash, why !?
//		[responseData release];
//		responseData = nil;
	}
}


#pragma mark NSXMLParser

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	if (qName)
	{
		elementName = qName;
	}
	
	if ([elementName isEqualToString:@"result"]) {
		_contentOfProperty = [NSMutableString string];
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{     
	if (qName)
	{
		elementName = qName;
	}
	
	if ([elementName isEqualToString:@"result"]) {
		if ([_contentOfProperty intValue] > _serverResult) {
			_serverResult = [_contentOfProperty intValue];
		}
	}
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if (_contentOfProperty)
	{
		// If the current element is one whose content we care about, append 'string'
		// to the property that holds the content of the current element.
		if (string != nil)
		{
			[_contentOfProperty appendString:string];
		}
	}
}


#pragma mark GetterSetter

- (NSString *) applicationName
{
	NSString *applicationName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleExecutable"];
	
	if (!applicationName)
		applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleExecutable"];
	
	return applicationName;
}


- (NSString*) applicationVersionString
{
	NSString* string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleShortVersionString"];
	
	if (!string)
		string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleShortVersionString"];
	
	return string;
}

- (NSString *) applicationVersion
{
	NSString* string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleVersion"];
	
	if (!string)
		string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleVersion"];
	
	return string;
}

@end




@implementation CrashReportSenderUI

- (id)init:(id)delegate crashFile:(NSString *)crashFile companyName:(NSString *)companyName applicationName:(NSString *)applicationName
{
	[super init];
	self = [[CrashReportSenderUI alloc] initWithWindowNibName: @"CrashReporterMain"];

	if ( self != nil)
	{
		_xml = nil;
		_delegate = delegate;
		_crashFile = crashFile;
		_companyName = companyName;
		_applicationName = applicationName;
		[self setShowComments: YES];
		[self setShowDetails: NO];
	}
	return self;	
}


- (void) endCrashReporter
{
	[[self window] close];
}


- (IBAction) showComments: (id) sender
{
	NSRect windowFrame = [[self window] frame];
	
	if ([sender intValue])
	{
		[self setShowComments: NO];
		
		windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + 105);
		[[self window] setFrame: windowFrame
						display: YES
						animate: YES];
		
		[self setShowComments: YES];
	}
	else
	{
		[self setShowComments: NO];
		
		windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - 105);
		[[self window] setFrame: windowFrame
						display: YES
						animate: YES];
	}
}


- (IBAction) showDetails:(id)sender
{
	NSRect windowFrame = [[self window] frame];

	windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + 399);
	[[self window] setFrame: windowFrame
					display: YES
					animate: YES];
	
	[self setShowDetails:YES];

}


- (IBAction) hideDetails:(id)sender
{
	NSRect windowFrame = [[self window] frame];

	[self setShowDetails:NO];

	windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - 399);
	[[self window] setFrame: windowFrame
					display: YES
					animate: YES];
}


- (IBAction) cancelReport:(id)sender
{
	[self endCrashReporter];

	if ( _delegate != nil && [_delegate respondsToSelector:@selector(cancelReport)])
		[_delegate cancelReport];
	
	[NSApp abortModal];
}


- (IBAction) submitReport:(id)sender
{
	[submitButton setEnabled:NO];
	
	[[self window] makeFirstResponder: nil];
	
	OSErr err;
	
	NSString *userid = @"";
	NSString *contact = @"";
	
	NSString *notes = [NSString stringWithFormat:@"Comments:\n%@\n\nConsole:\n%@", [descriptionTextField stringValue], _consoleContent];	
	
	SInt32 versionMajor, versionMinor, versionBugFix;
	if ((err = Gestalt(gestaltSystemVersionMajor, &versionMajor)) != noErr) versionMajor = 0;
	if ((err = Gestalt(gestaltSystemVersionMinor, &versionMinor)) != noErr)  versionMinor= 0;
	if ((err = Gestalt(gestaltSystemVersionBugFix, &versionBugFix)) != noErr) versionBugFix = 0;
	
	_xml = [[NSString stringWithFormat:@"<crash><applicationname>%s</applicationname><bundleidentifier>%s</bundleidentifier><systemversion>%@</systemversion><senderversion>%@</senderversion><version>%@</version><userid>%@</userid><contact>%@</contact><description><![CDATA[%@]]></description><log><![CDATA[%@]]></log></crash>",
			[[_delegate applicationName] UTF8String],
			[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] UTF8String],
			[NSString stringWithFormat:@"%i.%i.%i", versionMajor, versionMinor, versionBugFix],
			[_delegate applicationVersion],
			[_delegate applicationVersion],
			userid,
			contact,
			notes,
			_crashLogContent
			] retain];
	
	[self endCrashReporter];

	if ( _delegate != nil && [_delegate respondsToSelector:@selector(sendReport:)])
		[_delegate sendReport:_xml];

	[NSApp abortModal];
}


- (void) askCrashReportDetails
{
	NSError *error;
	
	[[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Problem Report for %@", @"Window title"), _applicationName]];

	[[descriptionTextField cell] setPlaceholderString:NSLocalizedString(@"Please describe any steps needed to trigger the problem", @"User description placeholder")];
	[noteText setStringValue:NSLocalizedString(@"No personal information will be sent with this report.", @"Note text")];

	// get the crash log
	NSString *crashLogs = [NSString stringWithContentsOfFile:_crashFile encoding:NSUTF8StringEncoding error:&error];
	NSString *lastCrash = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
	
	_crashLogContent = lastCrash;
	
	// get the console log
	NSEnumerator *theEnum = [[[NSString stringWithContentsOfFile:@"/private/var/log/system.log" encoding:NSUTF8StringEncoding error:&error] componentsSeparatedByString: @"\n"] objectEnumerator];
	NSString* currentObject;
	NSMutableArray* applicationStrings = [NSMutableArray array];
	
	NSString* searchString = [[_delegate applicationName] stringByAppendingString:@"["];
	while (currentObject = [theEnum nextObject])
	{
		if ([currentObject rangeOfString:searchString].location != NSNotFound)
			[applicationStrings addObject: currentObject];
	}
	
	_consoleContent = [NSMutableString string];
	
	int i;
	for(i = [applicationStrings count]-1; (i>=0 && i>[applicationStrings count]-100); i--) {
		[_consoleContent appendString:[applicationStrings objectAtIndex:i]];
		[_consoleContent appendString:@"\n"];
	}
	
    // Now limit the content to CRASHREPORTSENDER_MAX_CONSOLE_SIZE (default: 50kByte)
    if ([_consoleContent length] > CRASHREPORTSENDER_MAX_CONSOLE_SIZE)
    {
        _consoleContent = (NSMutableString *)[_consoleContent substringWithRange:NSMakeRange([_consoleContent length]-CRASHREPORTSENDER_MAX_CONSOLE_SIZE-1, CRASHREPORTSENDER_MAX_CONSOLE_SIZE)]; 
    }
        
	[crashLogTextView setString:[NSString stringWithFormat:@"%@\n\n%@", _crashLogContent, _consoleContent]];


	NSBeep();
	[NSApp runModalForWindow:[self window]];
}


- (void)dealloc
{
	_companyName = nil;
	_delegate = nil;
	
	[super dealloc];
}


- (BOOL)showComments
{
	return showComments;
}


- (void)setShowComments:(BOOL)value
{
	showComments = value;
}


- (BOOL)showDetails
{
	return showDetails;
}


- (void)setShowDetails:(BOOL)value
{
	showDetails = value;
}

@end

