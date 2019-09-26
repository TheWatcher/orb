## @file
# This file contains the implementation of the new page.
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
package ORB::New;

use strict;
use parent qw(ORB::Common); # This class extends the ORB common class
use experimental qw(smartmatch);
use v5.14;
use JSON;


# ============================================================================
#  UI handler/dispatcher functions

## @method $ _generate_new()
# Build the page containing the recipe creation form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_new {
    my $self = shift;
    my ($args, $errors);

    # User must have recipe create to proceed.
    return $self -> _fatal_error("{L_PERMISSION_FAILED_SUMMARY}")
        unless($self -> check_permission('recipe.create'));

    if($self -> {"cgi"} -> param("newrecipe")) {
        $self -> log("recipe.new", "User has submitted data for new recipe");

        # Do all the validation, and if there's no errors then add the recipe
        ($args, $errors) = $self -> _validate_recipe();
        if(!$errors) {
            # No errors, try adding the recipe
            $args -> {"creatorid"} = $self -> {"session"} -> get_session_userid();
            $args -> {"id"} = $self -> {"system"} -> {"recipe"} -> create($args)
                or $errors = $self -> {"template"} -> load_template("error/error_item.tem",
                                                                    { "%(error)s" => $self -> {"system"} -> {"recipe"} -> errstr() });

            # Did the addition work? If so, send the user to the view page for the new recipe
            return $self -> redirect($self -> build_url(block    => "view",
                                                        pathinfo => [ $args -> {"id"} ],
                                                        params   => "",
                                                        api      => []))
                if(!$errors);
        }
    }

    # Wrap the errors if there are any
    if($errors) {
        $self -> log("recipe.new", "Errors detected in addition: $errors");

        my $errorlist = $self -> {"template"} -> load_template("error/error_list.tem", {"%(message)s"  => "{L_NEW_ERRORS}",
                                                                                        "%(errors)s" => $errors });
        $errors = $self -> {"template"} -> load_template("error/page_error.tem", { "%(message)s" => $errorlist });
    }

    # Prebuild arrays for temptypes, units, and prep methods
    my $temptypes = $self -> _build_temptypes();
    my $units     = $self -> _get_units();
    my $preps     = $self -> _get_prepmethods();

    # And convert them to optionlists for the later template call
    my $unitopts   = $self -> {"template"} -> build_optionlist($units);
    my $prepopts   = $self -> {"template"} -> build_optionlist($preps);

    # Build the list of ingredients
    my $ingredients = $self -> _build_ingredients($args);

    # Build up the type and status data
    my $typeopts   = $self -> {"template"} -> build_optionlist($self -> {"system"} -> {"entities"} -> {"types"}  -> as_options(1),
                                                               $args -> {"type"});

    my $statusopts = $self -> {"template"} -> build_optionlist($self -> {"system"} -> {"entities"} -> {"states"} -> as_options(1, visible => {value => 1}),
                                                               $args -> {"status"});

    # Convert the time fields
    my ($preptime, $prepsecs) = ("", 0);
    if($args -> {"preptime"}) {
        $prepsecs = $args -> {"preptime"} * 60;
        $preptime = $self -> _build_timereq($prepsecs);
    }

    my ($cooktime, $cooksecs) = ("", 0);
    if($args -> {"cooktime"}) {
        $cooksecs = $args -> {"cooktime"} * 60;
        $cooktime = $self -> _build_timereq($cooksecs);
    }

    # Convert tags - can't use build_optionlist because all of them need to be selected.
    my $taglist = "";
    if($args -> {"tags"}) {
        my @tags = split(/,/, $args -> {"tags"});

        foreach my $tag (@tags) {
            $taglist .= "<option selected=\"selected\">$tag</option>\n";
        }
    }

    # And squirt out the page content
    my $body  = $self -> {"template"} -> load_template("new/content.tem",
                                                       {
                                                           "%(errors)s"    => $errors,
                                                           "%(name)s"      => $args -> {"name"} // "",
                                                           "%(source)s"    => $args -> {"source"} // "",
                                                           "%(yield)s"     => $args -> {"yield"} // "",
                                                           "%(prepinfo)s"  => $args -> {"prepinfo"} // "",
                                                           "%(preptime)s"  => $preptime,
                                                           "%(prepsecs)s"  => $prepsecs,
                                                           "%(cooktime)s"  => $cooktime,
                                                           "%(cooksecs)s"  => $cooksecs,
                                                           "%(temp)s"      => $args -> {"temp"} // "",
                                                           "%(temptypes)s" => $self -> {"template"} -> build_optionlist($temptypes, $args -> {"temptype"}),
                                                           "%(types)s"     => $typeopts,
                                                           "%(units)s"     => $unitopts,
                                                           "%(preps)s"     => $prepopts,
                                                           "%(status)s"    => $statusopts,
                                                           "%(tags)s"      => $taglist,
                                                           "%(ingreds)s"   => $ingredients,
                                                           "%(method)s"    => $args -> {"method"} // "",
                                                           "%(notes)s"     => $args -> {"notes"} // "",
                                                       });

    return ($self -> {"template"} -> replace_langvar("NEW_TITLE"),
            $body,
            $self -> {"template"} -> load_template("new/extrahead.tem"),
            $self -> {"template"} -> load_template("new/extrajs.tem"));
}


## @method private @ _fatal_error($error)
# Generate the tile and content for an error page.
#
# @param error A string containing the error message to display
# @return The title of the error page and an error message to place in the page.
sub _fatal_error {
    my $self  = shift;
    my $error = shift;

    return ("{L_VIEW_ERROR_FATAL}",
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

    my ($title, $body, $extrahead, $extrajs) = $self -> _generate_new();

    # Done generating the page content, return the filled in page template
    return $self -> generate_orb_page(title     => $title,
                                      content   => $body,
                                      extrahead => $extrahead,
                                      extrajs   => $extrajs,
                                      active    => '-',
                                      doclink   => 'summary');
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