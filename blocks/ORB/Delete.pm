## @file
# This file contains the implementation of the delete page.
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
# along with this program.  If not, see http://www.gnu.org/licenses/.

## @class
package ORB::Edit;

use strict;
use parent qw(ORB::Common); # This class extends the ORB common class
use experimental qw(smartmatch);
use v5.14;
use JSON;


sub _generate_delete {
    my $self     = shift;
    my $recipeid = shift;
    my $errors;

    # Recipe ID must be purely numeric for edits
    return $self -> _fatal_error("{L_DELETE_FAILED_BADID}")
        unless($recipeid =~ /^\d+$/);

    # Try to fetch the data.
    my $recipe = $self -> {"system"} -> {"recipe"} -> get_recipe($recipeid);
    return $self -> _fatal_error("{L_DELETE_FAILED_NOTFOUND}")
        unless($recipe -> {"id"});

    # User must have recipe edit to proceed.
    return $self -> _fatal_error("{L_PERMISSION_FAILED_SUMMARY}")
        unless($self -> check_permission('recipe.edit', $recipe -> {"metadata_id"}));

    $args -> {"id"} = $self -> {"system"} -> {"recipe"} -> set_status($recipe -> {"id"},
                                                                      $self -> {"settings"} -> {"config"} -> {"Recipe:status:deleted"} // "Deleted"
                                                                      $self -> {"session"} -> get_session_userid())
        or $errors = $self -> {"template"} -> load_template("error/error_item.tem",
                                                            { "%(error)s" => $self -> {"system"} -> {"recipe"} -> errstr() });

    # Did the delete work? If so, send the user to the list page
    return $self -> redirect($self -> build_url(block    => "list",
                                                pathinfo => [ uc(substr($recipe -> {"name"}, 0, 1)) ],
                                                params   => "",
                                                api      => []))
        if(!$errors);

    return $self -> _fatal_error($self -> {"template"} -> load_template("error/error_list.tem",
                                                                        {
                                                                            "%(message)s" => "{L_DELETE_FAILED}",
                                                                            "%(errors)s"  => $errors
                                                                        }));
}


## @method private @ _fatal_error($error)
# Generate the tile and content for an error page.
#
# @param error A string containing the error message to display
# @return The title of the error page and an error message to place in the page.
sub _fatal_error {
    my $self  = shift;
    my $error = shift;

    return ("{L_DELETE_ERROR_FATAL}",
            $self -> {"template"} -> load_template("error/page_error.tem",
                                                   { "%(message)s"    => $error,
                                                     "%(url-logout)s" => $self -> build_url(block => "login", pathinfo => ["signout"])
                                                   })
           );
}


## @method private $ _dispatch_ui()
# Implements the core behaviour dispatcher for non-api functions. This will
# inspect the state of the pathinfo and invoke the appropriate handler
# function to generate content for the user.
#
# @return A string containing the page HTML.
sub _dispatch_ui {
    my $self = shift;

    my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");
    my ($title, $body, $extrahead, $extrajs) = $self -> _generate_delete($pathinfo[0]);

    # Done generating the page content, return the filled in page template
    return $self -> generate_orb_page(title     => $title,
                                      content   => $body,
                                      extrahead => $extrahead,
                                      extrajs   => $extrajs,
                                      active    => '-',
                                      doclink   => 'delete');
}


# ============================================================================
#  Module interface functions

## @method $ page_display()
# Generate the page content for this module.
sub page_display {
    my $self = shift;

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # API call - dispatch to appropriate handler.
        given($apiop) {
            default {
                return $self -> api_response($self -> api_errorhash('bad_op',
                                                                    $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        return $self -> _dispatch_ui();
    }
}


1;