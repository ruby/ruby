Search = function(data, input, result) {
  this.data = data;
  this.$input = $(input);
  this.$result = $(result);

  this.$current = null;
  this.$view = this.$result.parent();
  this.searcher = new Searcher(data.index);
  this.init();
}

Search.prototype = $.extend({}, Navigation, new function() {
  var suid = 1;

  this.init = function() {
    var _this = this;
    var observer = function(e) {
      switch(e.originalEvent.keyCode) {
        case 38: // Event.KEY_UP
        case 40: // Event.KEY_DOWN
          return;
      }
      _this.search(_this.$input[0].value);
    };
    this.$input.keyup(observer);
    this.$input.click(observer); // mac's clear field

    this.searcher.ready(function(results, isLast) {
      _this.addResults(results, isLast);
    })

    this.initNavigation();
    this.setNavigationActive(false);
  }

  this.search = function(value, selectFirstMatch) {
    value = jQuery.trim(value).toLowerCase();
    if (value) {
      this.setNavigationActive(true);
    } else {
      this.setNavigationActive(false);
    }

    if (value == '') {
      this.lastQuery = value;
      this.$result.empty();
      this.$result.attr('aria-expanded', 'false');
      this.setNavigationActive(false);
    } else if (value != this.lastQuery) {
      this.lastQuery = value;
      this.$result.attr('aria-busy',     'true');
      this.$result.attr('aria-expanded', 'true');
      this.firstRun = true;
      this.searcher.find(value);
    }
  }

  this.addResults = function(results, isLast) {
    var target = this.$result.get(0);
    if (this.firstRun && (results.length > 0 || isLast)) {
      this.$current = null;
      this.$result.empty();
    }

    for (var i=0, l = results.length; i < l; i++) {
      var item = this.renderItem.call(this, results[i]);
      item.setAttribute('id', 'search-result-' + target.childElementCount);
      target.appendChild(item);
    };

    if (this.firstRun && results.length > 0) {
      this.firstRun = false;
      this.$current = $(target.firstChild);
      this.$current.addClass('search-selected');
    }
    if (jQuery.browser.msie) this.$element[0].className += '';

    if (isLast) this.$result.attr('aria-busy', 'false');
  }

  this.move = function(isDown) {
    if (!this.$current) return;
    var $next = this.$current[isDown ? 'next' : 'prev']();
    if ($next.length) {
      this.$current.removeClass('search-selected');
      $next.addClass('search-selected');
      this.$input.attr('aria-activedescendant', $next.attr('id'));
      this.scrollIntoView($next[0], this.$view[0]);
      this.$current = $next;
      this.$input.val($next[0].firstChild.firstChild.text);
      this.$input.select();
    }
    return true;
  }

  this.hlt = function(html) {
    return this.escapeHTML(html).
      replace(/\u0001/g, '<em>').
      replace(/\u0002/g, '</em>');
  }

  this.escapeHTML = function(html) {
    return html.replace(/[&<>]/g, function(c) {
      return '&#' + c.charCodeAt(0) + ';';
    });
  }

});

