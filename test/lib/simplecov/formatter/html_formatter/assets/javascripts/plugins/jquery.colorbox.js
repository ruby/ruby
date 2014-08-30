// ColorBox v1.3.20.1 - jQuery lightbox plugin
// (c) 2011 Jack Moore - jacklmoore.com
// License: http://www.opensource.org/licenses/mit-license.php
(function ($, document, window) {
	var
	// Default settings object.
	// See http://jacklmoore.com/colorbox for details.
	defaults = {
		transition: "elastic",
		speed: 300,
		width: false,
		initialWidth: "600",
		innerWidth: false,
		maxWidth: false,
		height: false,
		initialHeight: "450",
		innerHeight: false,
		maxHeight: false,
		scalePhotos: true,
		scrolling: true,
		inline: false,
		html: false,
		iframe: false,
		fastIframe: true,
		photo: false,
		href: false,
		title: false,
		rel: false,
		opacity: 0.9,
		preloading: true,

		current: "image {current} of {total}",
		previous: "previous",
		next: "next",
		close: "close",
		xhrError: "This content failed to load.",
		imgError: "This image failed to load.",

		open: false,
		returnFocus: true,
		reposition: true,
		loop: true,
		slideshow: false,
		slideshowAuto: true,
		slideshowSpeed: 2500,
		slideshowStart: "start slideshow",
		slideshowStop: "stop slideshow",
		onOpen: false,
		onLoad: false,
		onComplete: false,
		onCleanup: false,
		onClosed: false,
		overlayClose: true,
		escKey: true,
		arrowKey: true,
		top: false,
		bottom: false,
		left: false,
		right: false,
		fixed: false,
		data: undefined
	},
	
	// Abstracting the HTML and event identifiers for easy rebranding
	colorbox = 'colorbox',
	prefix = 'cbox',
	boxElement = prefix + 'Element',
	
	// Events
	event_open = prefix + '_open',
	event_load = prefix + '_load',
	event_complete = prefix + '_complete',
	event_cleanup = prefix + '_cleanup',
	event_closed = prefix + '_closed',
	event_purge = prefix + '_purge',
	
	// Special Handling for IE
	isIE = !$.support.opacity && !$.support.style, // IE7 & IE8
	isIE6 = isIE && !window.XMLHttpRequest, // IE6
	event_ie6 = prefix + '_IE6',

	// Cached jQuery Object Variables
	$overlay,
	$box,
	$wrap,
	$content,
	$topBorder,
	$leftBorder,
	$rightBorder,
	$bottomBorder,
	$related,
	$window,
	$loaded,
	$loadingBay,
	$loadingOverlay,
	$title,
	$current,
	$slideshow,
	$next,
	$prev,
	$close,
	$groupControls,
	
	// Variables for cached values or use across multiple functions
	settings,
	interfaceHeight,
	interfaceWidth,
	loadedHeight,
	loadedWidth,
	element,
	index,
	photo,
	open,
	active,
	closing,
	loadingTimer,
	publicMethod,
	div = "div",
	init;

	// ****************
	// HELPER FUNCTIONS
	// ****************
	
	// Convience function for creating new jQuery objects
	function $tag(tag, id, css) {
		var element = document.createElement(tag);

		if (id) {
			element.id = prefix + id;
		}

		if (css) {
			element.style.cssText = css;
		}

		return $(element);
	}

	// Determine the next and previous members in a group.
	function getIndex(increment) {
		var
		max = $related.length,
		newIndex = (index + increment) % max;
		
		return (newIndex < 0) ? max + newIndex : newIndex;
	}

	// Convert '%' and 'px' values to integers
	function setSize(size, dimension) {
		return Math.round((/%/.test(size) ? ((dimension === 'x' ? winWidth() : winHeight()) / 100) : 1) * parseInt(size, 10));
	}
	
	// Checks an href to see if it is a photo.
	// There is a force photo option (photo: true) for hrefs that cannot be matched by this regex.
	function isImage(url) {
		return settings.photo || /\.(gif|png|jp(e|g|eg)|bmp|ico)((#|\?).*)?$/i.test(url);
	}
	
	function winWidth() {
		// $(window).width() is incorrect for some mobile browsers, but
		// window.innerWidth is unsupported in IE8 and lower.
		return window.innerWidth || $window.width();
	}

	function winHeight() {
		return window.innerHeight || $window.height();
	}

	// Assigns function results to their respective properties
	function makeSettings() {
		var i,
			data = $.data(element, colorbox);
		
		if (data == null) {
			settings = $.extend({}, defaults);
			if (console && console.log) {
				console.log('Error: cboxElement missing settings object');
			}
		} else {
			settings = $.extend({}, data);
		}
		
		for (i in settings) {
			if ($.isFunction(settings[i]) && i.slice(0, 2) !== 'on') { // checks to make sure the function isn't one of the callbacks, they will be handled at the appropriate time.
				settings[i] = settings[i].call(element);
			}
		}
		
		settings.rel = settings.rel || element.rel || $(element).data('rel') || 'nofollow';
		settings.href = settings.href || $(element).attr('href');
		settings.title = settings.title || element.title;
		
		if (typeof settings.href === "string") {
			settings.href = $.trim(settings.href);
		}
	}

	function trigger(event, callback) {
		$.event.trigger(event);
		if (callback) {
			callback.call(element);
		}
	}

	// Slideshow functionality
	function slideshow() {
		var
		timeOut,
		className = prefix + "Slideshow_",
		click = "click." + prefix,
		start,
		stop,
		clear;
		
		if (settings.slideshow && $related[1]) {
			start = function () {
				$slideshow
					.html(settings.slideshowStop)
					.unbind(click)
					.bind(event_complete, function () {
						if (settings.loop || $related[index + 1]) {
							timeOut = setTimeout(publicMethod.next, settings.slideshowSpeed);
						}
					})
					.bind(event_load, function () {
						clearTimeout(timeOut);
					})
					.one(click + ' ' + event_cleanup, stop);
				$box.removeClass(className + "off").addClass(className + "on");
				timeOut = setTimeout(publicMethod.next, settings.slideshowSpeed);
			};
			
			stop = function () {
				clearTimeout(timeOut);
				$slideshow
					.html(settings.slideshowStart)
					.unbind([event_complete, event_load, event_cleanup, click].join(' '))
					.one(click, function () {
						publicMethod.next();
						start();
					});
				$box.removeClass(className + "on").addClass(className + "off");
			};
			
			if (settings.slideshowAuto) {
				start();
			} else {
				stop();
			}
		} else {
			$box.removeClass(className + "off " + className + "on");
		}
	}

	function launch(target) {
		if (!closing) {
			
			element = target;
			
			makeSettings();
			
			$related = $(element);
			
			index = 0;
			
			if (settings.rel !== 'nofollow') {
				$related = $('.' + boxElement).filter(function () {
					var data = $.data(this, colorbox),
						relRelated;

					if (data) {
						relRelated =  $(this).data('rel') || data.rel || this.rel;
					}
					
					return (relRelated === settings.rel);
				});
				index = $related.index(element);
				
				// Check direct calls to ColorBox.
				if (index === -1) {
					$related = $related.add(element);
					index = $related.length - 1;
				}
			}
			
			if (!open) {
				open = active = true; // Prevents the page-change action from queuing up if the visitor holds down the left or right keys.
				
				$box.show();
				
				if (settings.returnFocus) {
					$(element).blur().one(event_closed, function () {
						$(this).focus();
					});
				}
				
				// +settings.opacity avoids a problem in IE when using non-zero-prefixed-string-values, like '.5'
				$overlay.css({"opacity": +settings.opacity, "cursor": settings.overlayClose ? "pointer" : "auto"}).show();
				
				// Opens inital empty ColorBox prior to content being loaded.
				settings.w = setSize(settings.initialWidth, 'x');
				settings.h = setSize(settings.initialHeight, 'y');
				publicMethod.position();
				
				if (isIE6) {
					$window.bind('resize.' + event_ie6 + ' scroll.' + event_ie6, function () {
						$overlay.css({width: winWidth(), height: winHeight(), top: $window.scrollTop(), left: $window.scrollLeft()});
					}).trigger('resize.' + event_ie6);
				}
				
				trigger(event_open, settings.onOpen);
				
				$groupControls.add($title).hide();
				
				$close.html(settings.close).show();
			}
			
			publicMethod.load(true);
		}
	}

	// ColorBox's markup needs to be added to the DOM prior to being called
	// so that the browser will go ahead and load the CSS background images.
	function appendHTML() {
		if (!$box && document.body) {
			init = false;

			$window = $(window);
			$box = $tag(div).attr({id: colorbox, 'class': isIE ? prefix + (isIE6 ? 'IE6' : 'IE') : ''}).hide();
			$overlay = $tag(div, "Overlay", isIE6 ? 'position:absolute' : '').hide();
			$loadingOverlay = $tag(div, "LoadingOverlay").add($tag(div, "LoadingGraphic"));
			$wrap = $tag(div, "Wrapper");
			$content = $tag(div, "Content").append(
				$loaded = $tag(div, "LoadedContent", 'width:0; height:0; overflow:hidden'),
				$title = $tag(div, "Title"),
				$current = $tag(div, "Current"),
				$next = $tag(div, "Next"),
				$prev = $tag(div, "Previous"),
				$slideshow = $tag(div, "Slideshow").bind(event_open, slideshow),
				$close = $tag(div, "Close")
			);
			
			$wrap.append( // The 3x3 Grid that makes up ColorBox
				$tag(div).append(
					$tag(div, "TopLeft"),
					$topBorder = $tag(div, "TopCenter"),
					$tag(div, "TopRight")
				),
				$tag(div, false, 'clear:left').append(
					$leftBorder = $tag(div, "MiddleLeft"),
					$content,
					$rightBorder = $tag(div, "MiddleRight")
				),
				$tag(div, false, 'clear:left').append(
					$tag(div, "BottomLeft"),
					$bottomBorder = $tag(div, "BottomCenter"),
					$tag(div, "BottomRight")
				)
			).find('div div').css({'float': 'left'});
			
			$loadingBay = $tag(div, false, 'position:absolute; width:9999px; visibility:hidden; display:none');
			
			$groupControls = $next.add($prev).add($current).add($slideshow);

			$(document.body).append($overlay, $box.append($wrap, $loadingBay));
		}
	}

	// Add ColorBox's event bindings
	function addBindings() {
		if ($box) {
			if (!init) {
				init = true;

				// Cache values needed for size calculations
				interfaceHeight = $topBorder.height() + $bottomBorder.height() + $content.outerHeight(true) - $content.height();//Subtraction needed for IE6
				interfaceWidth = $leftBorder.width() + $rightBorder.width() + $content.outerWidth(true) - $content.width();
				loadedHeight = $loaded.outerHeight(true);
				loadedWidth = $loaded.outerWidth(true);
				
				// Setting padding to remove the need to do size conversions during the animation step.
				$box.css({"padding-bottom": interfaceHeight, "padding-right": interfaceWidth});

				// Anonymous functions here keep the public method from being cached, thereby allowing them to be redefined on the fly.
				$next.click(function () {
					publicMethod.next();
				});
				$prev.click(function () {
					publicMethod.prev();
				});
				$close.click(function () {
					publicMethod.close();
				});
				$overlay.click(function () {
					if (settings.overlayClose) {
						publicMethod.close();
					}
				});
				
				// Key Bindings
				$(document).bind('keydown.' + prefix, function (e) {
					var key = e.keyCode;
					if (open && settings.escKey && key === 27) {
						e.preventDefault();
						publicMethod.close();
					}
					if (open && settings.arrowKey && $related[1]) {
						if (key === 37) {
							e.preventDefault();
							$prev.click();
						} else if (key === 39) {
							e.preventDefault();
							$next.click();
						}
					}
				});

				$('.' + boxElement, document).live('click', function (e) {
					// ignore non-left-mouse-clicks and clicks modified with ctrl / command, shift, or alt.
					// See: http://jacklmoore.com/notes/click-events/
					if (!(e.which > 1 || e.shiftKey || e.altKey || e.metaKey)) {
						e.preventDefault();
						launch(this);
					}
				});
			}
			return true;
		}
		return false;
	}

	// Don't do anything if ColorBox already exists.
	if ($.colorbox) {
		return;
	}

	// Append the HTML when the DOM loads
	$(appendHTML);


	// ****************
	// PUBLIC FUNCTIONS
	// Usage format: $.fn.colorbox.close();
	// Usage from within an iframe: parent.$.fn.colorbox.close();
	// ****************
	
	publicMethod = $.fn[colorbox] = $[colorbox] = function (options, callback) {
		var $this = this;
		
		options = options || {};
		
		appendHTML();

		if (addBindings()) {
			if (!$this[0]) {
				if ($this.selector) { // if a selector was given and it didn't match any elements, go ahead and exit.
					return $this;
				}
				// if no selector was given (ie. $.colorbox()), create a temporary element to work with
				$this = $('<a/>');
				options.open = true; // assume an immediate open
			}
			
			if (callback) {
				options.onComplete = callback;
			}
			
			$this.each(function () {
				$.data(this, colorbox, $.extend({}, $.data(this, colorbox) || defaults, options));
			}).addClass(boxElement);
			
			if (($.isFunction(options.open) && options.open.call($this)) || options.open) {
				launch($this[0]);
			}
		}
		
		return $this;
	};

	publicMethod.position = function (speed, loadedCallback) {
		var
		css,
		top = 0,
		left = 0,
		offset = $box.offset(),
		scrollTop,
		scrollLeft;
		
		$window.unbind('resize.' + prefix);

		// remove the modal so that it doesn't influence the document width/height
		$box.css({top: -9e4, left: -9e4});

		scrollTop = $window.scrollTop();
		scrollLeft = $window.scrollLeft();

		if (settings.fixed && !isIE6) {
			offset.top -= scrollTop;
			offset.left -= scrollLeft;
			$box.css({position: 'fixed'});
		} else {
			top = scrollTop;
			left = scrollLeft;
			$box.css({position: 'absolute'});
		}

		// keeps the top and left positions within the browser's viewport.
		if (settings.right !== false) {
			left += Math.max(winWidth() - settings.w - loadedWidth - interfaceWidth - setSize(settings.right, 'x'), 0);
		} else if (settings.left !== false) {
			left += setSize(settings.left, 'x');
		} else {
			left += Math.round(Math.max(winWidth() - settings.w - loadedWidth - interfaceWidth, 0) / 2);
		}
		
		if (settings.bottom !== false) {
			top += Math.max(winHeight() - settings.h - loadedHeight - interfaceHeight - setSize(settings.bottom, 'y'), 0);
		} else if (settings.top !== false) {
			top += setSize(settings.top, 'y');
		} else {
			top += Math.round(Math.max(winHeight() - settings.h - loadedHeight - interfaceHeight, 0) / 2);
		}

		$box.css({top: offset.top, left: offset.left});

		// setting the speed to 0 to reduce the delay between same-sized content.
		speed = ($box.width() === settings.w + loadedWidth && $box.height() === settings.h + loadedHeight) ? 0 : speed || 0;
		
		// this gives the wrapper plenty of breathing room so it's floated contents can move around smoothly,
		// but it has to be shrank down around the size of div#colorbox when it's done.  If not,
		// it can invoke an obscure IE bug when using iframes.
		$wrap[0].style.width = $wrap[0].style.height = "9999px";
		
		function modalDimensions(that) {
			$topBorder[0].style.width = $bottomBorder[0].style.width = $content[0].style.width = that.style.width;
			$content[0].style.height = $leftBorder[0].style.height = $rightBorder[0].style.height = that.style.height;
		}

		css = {width: settings.w + loadedWidth, height: settings.h + loadedHeight, top: top, left: left};
		if(speed===0){ // temporary workaround to side-step jQuery-UI 1.8 bug (http://bugs.jquery.com/ticket/12273)
			$box.css(css);
		}
		$box.dequeue().animate(css, {
			duration: speed,
			complete: function () {
				modalDimensions(this);
				
				active = false;
				
				// shrink the wrapper down to exactly the size of colorbox to avoid a bug in IE's iframe implementation.
				$wrap[0].style.width = (settings.w + loadedWidth + interfaceWidth) + "px";
				$wrap[0].style.height = (settings.h + loadedHeight + interfaceHeight) + "px";
				
				if (settings.reposition) {
					setTimeout(function () {  // small delay before binding onresize due to an IE8 bug.
						$window.bind('resize.' + prefix, publicMethod.position);
					}, 1);
				}

				if (loadedCallback) {
					loadedCallback();
				}
			},
			step: function () {
				modalDimensions(this);
			}
		});
	};

	publicMethod.resize = function (options) {
		if (open) {
			options = options || {};
			
			if (options.width) {
				settings.w = setSize(options.width, 'x') - loadedWidth - interfaceWidth;
			}
			if (options.innerWidth) {
				settings.w = setSize(options.innerWidth, 'x');
			}
			$loaded.css({width: settings.w});
			
			if (options.height) {
				settings.h = setSize(options.height, 'y') - loadedHeight - interfaceHeight;
			}
			if (options.innerHeight) {
				settings.h = setSize(options.innerHeight, 'y');
			}
			if (!options.innerHeight && !options.height) {
				$loaded.css({height: "auto"});
				settings.h = $loaded.height();
			}
			$loaded.css({height: settings.h});
			
			publicMethod.position(settings.transition === "none" ? 0 : settings.speed);
		}
	};

	publicMethod.prep = function (object) {
		if (!open) {
			return;
		}
		
		var callback, speed = settings.transition === "none" ? 0 : settings.speed;
		
		$loaded.remove();
		$loaded = $tag(div, 'LoadedContent').append(object);
		
		function getWidth() {
			settings.w = settings.w || $loaded.width();
			settings.w = settings.mw && settings.mw < settings.w ? settings.mw : settings.w;
			return settings.w;
		}
		function getHeight() {
			settings.h = settings.h || $loaded.height();
			settings.h = settings.mh && settings.mh < settings.h ? settings.mh : settings.h;
			return settings.h;
		}
		
		$loaded.hide()
		.appendTo($loadingBay.show())// content has to be appended to the DOM for accurate size calculations.
		.css({width: getWidth(), overflow: settings.scrolling ? 'auto' : 'hidden'})
		.css({height: getHeight()})// sets the height independently from the width in case the new width influences the value of height.
		.prependTo($content);
		
		$loadingBay.hide();
		
		// floating the IMG removes the bottom line-height and fixed a problem where IE miscalculates the width of the parent element as 100% of the document width.
		//$(photo).css({'float': 'none', marginLeft: 'auto', marginRight: 'auto'});
		
		$(photo).css({'float': 'none'});
		
		// Hides SELECT elements in IE6 because they would otherwise sit on top of the overlay.
		if (isIE6) {
			$('select').not($box.find('select')).filter(function () {
				return this.style.visibility !== 'hidden';
			}).css({'visibility': 'hidden'}).one(event_cleanup, function () {
				this.style.visibility = 'inherit';
			});
		}
		
		callback = function () {
			var preload,
				i,
				total = $related.length,
				iframe,
				frameBorder = 'frameBorder',
				allowTransparency = 'allowTransparency',
				complete,
				src,
				img,
				data;
			
			if (!open) {
				return;
			}
			
			function removeFilter() {
				if (isIE) {
					$box[0].style.removeAttribute('filter');
				}
			}
			
			complete = function () {
				clearTimeout(loadingTimer);
				// Detaching forces Andriod stock browser to redraw the area underneat the loading overlay.  Hiding alone isn't enough.
				$loadingOverlay.detach().hide();
				trigger(event_complete, settings.onComplete);
			};
			
			if (isIE) {
				//This fadeIn helps the bicubic resampling to kick-in.
				if (photo) {
					$loaded.fadeIn(100);
				}
			}
			
			$title.html(settings.title).add($loaded).show();
			
			if (total > 1) { // handle grouping
				if (typeof settings.current === "string") {
					$current.html(settings.current.replace('{current}', index + 1).replace('{total}', total)).show();
				}
				
				$next[(settings.loop || index < total - 1) ? "show" : "hide"]().html(settings.next);
				$prev[(settings.loop || index) ? "show" : "hide"]().html(settings.previous);
				
				if (settings.slideshow) {
					$slideshow.show();
				}
				
				// Preloads images within a rel group
				if (settings.preloading) {
					preload = [
						getIndex(-1),
						getIndex(1)
					];
					while (i = $related[preload.pop()]) {
						data = $.data(i, colorbox);
						
						if (data && data.href) {
							src = data.href;
							if ($.isFunction(src)) {
								src = src.call(i);
							}
						} else {
							src = i.href;
						}

						if (isImage(src)) {
							img = new Image();
							img.src = src;
						}
					}
				}
			} else {
				$groupControls.hide();
			}
			
			if (settings.iframe) {
				iframe = $tag('iframe')[0];
				
				if (frameBorder in iframe) {
					iframe[frameBorder] = 0;
				}
				
				if (allowTransparency in iframe) {
					iframe[allowTransparency] = "true";
				}

				if (!settings.scrolling) {
					iframe.scrolling = "no";
				}
				
				$(iframe)
					.attr({
						src: settings.href,
						name: (new Date()).getTime(), // give the iframe a unique name to prevent caching
						'class': prefix + 'Iframe',
						allowFullScreen : true, // allow HTML5 video to go fullscreen
						webkitAllowFullScreen : true,
						mozallowfullscreen : true
					})
					.one('load', complete)
					.one(event_purge, function () {
						iframe.src = "//about:blank";
					})
					.appendTo($loaded);
				
				if (settings.fastIframe) {
					$(iframe).trigger('load');
				}
			} else {
				complete();
			}
			
			if (settings.transition === 'fade') {
				$box.fadeTo(speed, 1, removeFilter);
			} else {
				removeFilter();
			}
		};
		
		if (settings.transition === 'fade') {
			$box.fadeTo(speed, 0, function () {
				publicMethod.position(0, callback);
			});
		} else {
			publicMethod.position(speed, callback);
		}
	};

	publicMethod.load = function (launched) {
		var href, setResize, prep = publicMethod.prep;
		
		active = true;
		
		photo = false;
		
		element = $related[index];
		
		if (!launched) {
			makeSettings();
		}
		
		trigger(event_purge);
		
		trigger(event_load, settings.onLoad);
		
		settings.h = settings.height ?
				setSize(settings.height, 'y') - loadedHeight - interfaceHeight :
				settings.innerHeight && setSize(settings.innerHeight, 'y');
		
		settings.w = settings.width ?
				setSize(settings.width, 'x') - loadedWidth - interfaceWidth :
				settings.innerWidth && setSize(settings.innerWidth, 'x');
		
		// Sets the minimum dimensions for use in image scaling
		settings.mw = settings.w;
		settings.mh = settings.h;
		
		// Re-evaluate the minimum width and height based on maxWidth and maxHeight values.
		// If the width or height exceed the maxWidth or maxHeight, use the maximum values instead.
		if (settings.maxWidth) {
			settings.mw = setSize(settings.maxWidth, 'x') - loadedWidth - interfaceWidth;
			settings.mw = settings.w && settings.w < settings.mw ? settings.w : settings.mw;
		}
		if (settings.maxHeight) {
			settings.mh = setSize(settings.maxHeight, 'y') - loadedHeight - interfaceHeight;
			settings.mh = settings.h && settings.h < settings.mh ? settings.h : settings.mh;
		}
		
		href = settings.href;
		
		loadingTimer = setTimeout(function () {
			$loadingOverlay.show().appendTo($content);
		}, 100);
		
		if (settings.inline) {
			// Inserts an empty placeholder where inline content is being pulled from.
			// An event is bound to put inline content back when ColorBox closes or loads new content.
			$tag(div).hide().insertBefore($(href)[0]).one(event_purge, function () {
				$(this).replaceWith($loaded.children());
			});
			prep($(href));
		} else if (settings.iframe) {
			// IFrame element won't be added to the DOM until it is ready to be displayed,
			// to avoid problems with DOM-ready JS that might be trying to run in that iframe.
			prep(" ");
		} else if (settings.html) {
			prep(settings.html);
		} else if (isImage(href)) {
			$(photo = new Image())
			.addClass(prefix + 'Photo')
			.error(function () {
				settings.title = false;
				prep($tag(div, 'Error').html(settings.imgError));
			})
			.load(function () {
				var percent;
				photo.onload = null; //stops animated gifs from firing the onload repeatedly.
				
				if (settings.scalePhotos) {
					setResize = function () {
						photo.height -= photo.height * percent;
						photo.width -= photo.width * percent;
					};
					if (settings.mw && photo.width > settings.mw) {
						percent = (photo.width - settings.mw) / photo.width;
						setResize();
					}
					if (settings.mh && photo.height > settings.mh) {
						percent = (photo.height - settings.mh) / photo.height;
						setResize();
					}
				}
				
				if (settings.h) {
					photo.style.marginTop = Math.max(settings.h - photo.height, 0) / 2 + 'px';
				}
				
				if ($related[1] && (settings.loop || $related[index + 1])) {
					photo.style.cursor = 'pointer';
					photo.onclick = function () {
						publicMethod.next();
					};
				}
				
				if (isIE) {
					photo.style.msInterpolationMode = 'bicubic';
				}
				
				setTimeout(function () { // A pause because Chrome will sometimes report a 0 by 0 size otherwise.
					prep(photo);
				}, 1);
			});
			
			setTimeout(function () { // A pause because Opera 10.6+ will sometimes not run the onload function otherwise.
				photo.src = href;
			}, 1);
		} else if (href) {
			$loadingBay.load(href, settings.data, function (data, status, xhr) {
				prep(status === 'error' ? $tag(div, 'Error').html(settings.xhrError) : $(this).contents());
			});
		}
	};
		
	// Navigates to the next page/image in a set.
	publicMethod.next = function () {
		if (!active && $related[1] && (settings.loop || $related[index + 1])) {
			index = getIndex(1);
			publicMethod.load();
		}
	};
	
	publicMethod.prev = function () {
		if (!active && $related[1] && (settings.loop || index)) {
			index = getIndex(-1);
			publicMethod.load();
		}
	};

	// Note: to use this within an iframe use the following format: parent.$.fn.colorbox.close();
	publicMethod.close = function () {
		if (open && !closing) {
			
			closing = true;
			
			open = false;
			
			trigger(event_cleanup, settings.onCleanup);
			
			$window.unbind('.' + prefix + ' .' + event_ie6);
			
			$overlay.fadeTo(200, 0);
			
			$box.stop().fadeTo(300, 0, function () {
			
				$box.add($overlay).css({'opacity': 1, cursor: 'auto'}).hide();
				
				trigger(event_purge);
				
				$loaded.remove();
				
				setTimeout(function () {
					closing = false;
					trigger(event_closed, settings.onClosed);
				}, 1);
			});
		}
	};

	// Removes changes ColorBox made to the document, but does not remove the plugin
	// from jQuery.
	publicMethod.remove = function () {
		$([]).add($box).add($overlay).remove();
		$box = null;
		$('.' + boxElement)
			.removeData(colorbox)
			.removeClass(boxElement)
			.die();
	};

	// A method for fetching the current element ColorBox is referencing.
	// returns a jQuery object.
	publicMethod.element = function () {
		return $(element);
	};

	publicMethod.settings = defaults;

}(jQuery, document, window));