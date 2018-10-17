## @file
# This file contains the implementation of the edit page.
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


## @method private $ _convert_tags($tags)
# Convert a list of tags into a string that can be shown in the recipe
# page.
#
# @param tags A reference to a list of tag names.
# @return A string containing the tag list.
sub _convert_tags {
    my $self = shift;
    my $tags = shift;

    my @result;
    foreach my $tag (@{$tags}) {
        push(@result, $tag -> {"name"});
    }

    return join(",", @result);
}


## @method private void _convert_ingredients($args)
# Convert the ingredients list into a form that can be shown in the
# edit form. This fixes up some differences between the field names
# used in the result of get_recipe() and the ingredient generator.
#
# @param args A reference to the recipe data hash.
sub _convert_ingredients {
    my $self = shift;
    my $args = shift;

    foreach my $ingred (@{$args -> {"ingredients"}}) {
        if($ingred -> {"separator"}) {
            $ingred -> {"name"} = $ingred -> {"separator"};
        } else {
            $ingred -> {"name"} = $ingred -> {"ingredient"};
        }

        $ingred -> {"prep"} = $ingred -> {"prepmethod"};
    }
}


# ============================================================================
#  UI handler/dispatcher functions

## @method $ _generate_edit($recipeid)
# Build the page containing the recipe edit form.
#
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_edit {
    my $self     = shift;
    my $recipeid = shift;
    my ($args, $errors);

    # Recipe ID must be purely numeric for edits
    return $self -> _fatal_error("{L_EDIT_FAILED_BADID}")
        unless($recipeid =~ /^\d+$/);

    # Try to fetch the data.
    $args = $self -> {"system"} -> {"recipe"} -> get_recipe($recipeid);
    return $self -> _fatal_error("{L_EDIT_FAILED_NOTFOUND}")
        unless($args -> {"id"});

    $args -> {"tags"} = $self -> _convert_tags($args -> {"tags"});
    $self -> _convert_ingredients($args);

    # User must have recipe create to proceed.
    return $self -> _fatal_error("{L_PERMISSION_FAILED_SUMMARY}")
        unless($self -> check_permission('recipe.edit', $args -> {"metadata_id"}));

    if($self -> {"cgi"} -> param("editrecipe")) {
        $self -> log("recipe.edit", "User has submitted data for recipe $recipeid");

        $args = {};

        # Do all the validation, and if there's no errors then add the recipe
        ($args, $errors) = $self -> _validate_recipe();
        if(!$errors) {
            # No errors, try adding the recipe
            $args -> {"creatorid"} = $self -> {"session"} -> get_session_userid();
            $args -> {"origid"} = $recipeid;

            $args -> {"id"} = $self -> {"system"} -> {"recipe"} -> edit($args)
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
        $self -> log("new", "Errors detected in addition: $errors");

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
    my $body  = $self -> {"template"} -> load_template("edit/content.tem",
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

    return ($self -> {"template"} -> replace_langvar("EDIT_TITLE"),
            $body,
            $self -> {"template"} -> load_template("edit/extrahead.tem"),
            $self -> {"template"} -> load_template("edit/extrajs.tem"));
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

    my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");
    my ($title, $body, $extrahead, $extrajs) = $self -> _generate_edit($pathinfo[0]);

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