use strict;
use warnings;
use URI::Escape;

warn uri_escape_utf8(shift, "\x00-\x1f\x7f-\xff");
#warn uri_escape(shift);
