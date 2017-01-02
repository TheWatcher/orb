## @file
# This file contains the implementation of the ORB user toolbar.
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class ORB::Userbar
# The Userbar class encapsulates the code required to generate and
# manage the user toolbar.
package ORB::Userbar;

use strict;
use parent qw(ORB);
use experimental qw(smartmatch);
use v5.14;


# ==============================================================================
#  Bar generation

## @method $ block_display($title, $current, $doclink)
# Generate a user toolbar, populating it as needed to reflect the user's options
# at the current time.
#
# @param title   A string to show as the page title.
# @param current The current page name.
# @param doclink The name of a document link to include in the userbar. If not
#                supplied, no link is shown.
# @return A string containing the user toolbar html on success, undef on error.
sub block_display {
    my $self    = shift;
    my $title   = shift;
    my $current = shift;
    my $doclink = shift;

    $self -> clear_error();

    my $urls = { "signin"  => $self -> build_url(block => "login",
                                                fullurl  => 1,
                                                pathinfo => [],
                                                params   => {},
                                                forcessl => 1),
                 "signout" => $self -> build_url(block => "login",
                                                fullurl  => 1,
                                                pathinfo => [ "signout" ],
                                                params   => {},
                                                forcessl => 1),
                 "signup"  => $self -> build_url(block => "login",
                                                 fullurl  => 1,
                                                 pathinfo => [ "signup" ],
                                                 params   => {},
                                                 forcessl => 1),
                 "setpass" => $self -> build_url(block => "login",
                                                 fullurl  => 1,
                                                 pathinfo => [ "passchange" ],
                                                 params   => {},
                                                 forcessl => 1),
                 "front"   => $self -> build_url(block    => $self -> {"settings"} -> {"config"} -> {"default_block"},
                                                 fullurl  => 1,
                                                 pathinfo => [],
                                                 params   => {})
    };

    my $userprofile;

    # Is the user logged in?
    if(!$self -> {"session"} -> anonymous_session()) {
        my $user = $self -> {"session"} -> get_user_byid()
            or return $self -> self_error("Unable to obtain user data for logged in user. This should not happen!");

        # User is logged in, so actually reflect their current options and state
        $userprofile = $self -> {"template"} -> load_template("userbar/profile_signedin.tem",
                                                              { "%(realname)s"    => $user -> {"fullname"},
                                                                "%(username)s"    => $user -> {"username"},
                                                                "%(gravhash)s"    => $user -> {"gravatar_hash"},
                                                                "%(url-signout)s" => $urls -> {"signout"},
                                                                "%(url-setpass)s" => $urls -> {"setpass"},
                                                              });

    } else {
        my $signup = $self -> {"template"} -> load_template("userbar/profile_signup.tem")
            if($self -> {"settings"} -> {"config"} -> {"Login:allow_self_register"});

        $userprofile = $self -> {"template"} -> load_template("userbar/profile_signedout.tem",
                                                              { "%(signup)s"    => $signup,
                                                                "%(url-signin)s" => $urls -> {"signin"},
                                                                "%(url-signup)s" => $urls -> {"signup"},
                                                              });
    }

    return $self -> {"template"} -> load_template("userbar/userbar.tem",
                                                  { "%(pagename)s"  => $title,
                                                    "%(url-front)s" => $urls -> {"front"},
                                                    "%(profile)s"   => $userprofile});
}


## @method $ page_display()
# Produce the string containing this block's full page content. This is primarily provided for
# API operations that allow the user to change their profile and settings.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;
    my ($content, $extrahead, $title);

    if(!$self -> {"session"} -> anonymous_session()) {
        my $user = $self -> {"session"} -> get_user_byid()
            or return '';

        my $apiop = $self -> is_api_operation();
        if(defined($apiop)) {
            given($apiop) {
                default {
                    return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                             $self -> {"template"} -> replace_langvar("API_BAD_OP")))
                }
            }
        }
    }

    return "<p class=\"error\">".$self -> {"template"} -> replace_langvar("BLOCK_PAGE_DISPLAY")."</p>";
}

1;
