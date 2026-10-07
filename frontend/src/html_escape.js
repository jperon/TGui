(function() {
  // html_escape.coffee — shared HTML escaping for innerHTML sinks.
  // Exposes window.TdbHtml = { escape }. Loaded via backend/ui/scripts.moon
  // (SCRIPT_SRCS) BEFORE any module that calls it. Escapes the five HTML
  // significant characters; tolerates null/undefined (empty string) and
  // non-strings (String conversion).
  window.TdbHtml = {
    escape: function(s) {
      if (s == null) {
        return '';
      }
      return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }
  };

}).call(this);
