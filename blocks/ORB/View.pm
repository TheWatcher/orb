## @file
# This file contains the implementation of the view page.
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
package ORB::View;

use strict;
use parent qw(ORB); # This class extends the ORB block class
use experimental qw(smartmatch);
use Regexp::Common qw(URI);
use v5.14;

## @method private $ _resolve_recipe_name($rid)
# Given a recipe name, locate the recipe with that name if possible.
# If rid is purely numeric, this assumes it's already just an ID and
# returns it as-is, otherwise this will search for the recipe and
# return the ID of the recipe, or undef if it can't be found.
sub _resolve_recipe_name {
    my $self = shift;
    my $rid  = shift;

    return $rid if($rid =~ /^\d+$/);


}


## @method private $ _generate_ingredients($ingreds)
# Given an array of ingredients, convert them to a list of ingredients
# to show in the recipe.
#
# @param ingreds A reference to an array of ingredient hashes.
# @return A string containing the convered ingredient list.
sub _generate_ingredients {
    my $self    = shift;
    my $ingreds = shift;

    my @result;
    foreach my $ingred (@{$ingreds}) {
        if($ingred -> {"separator"}) {
            push(@result, $self -> {"template"} -> load_template("view/separator.tem",
                                                                 {
                                                                     "%(separator)s" => $ingred -> {"separator"}
                                                                 }));
        } else {
            my $units = $ingred -> {"units"} eq "None" ? "" : $ingred -> {"units"};
            my $quantity = $ingred -> {"quantity"} ? $ingred -> {"quantity"} : "";

            push(@result, $self -> {"template"} -> load_template("view/ingredient.tem",
                                                                 {
                                                                     "%(quantity)s"   => $quantity,
                                                                     "%(units)s"      => $units,
                                                                     "%(prepmethod)s" => $ingred -> {"prepmethod"},
                                                                     "%(ingredient)s" => $ingred -> {"ingredient"},
                                                                     "%(notes)s"      => $ingred -> {"notes"} ? "(".$ingred -> {"notes"}.")" : "",
                                                                 }));
        }
    }

    return join("\n", @result);
}


## @method private $ _generate_tags($tags)
# Convert a list of tags into a string that can be shown in the recipe
# page.
#
# @param tags A reference to a list of tag names.
# @return A string containing the tag list.
sub _generate_tags {
    my $self = shift;
    my $tags = shift;

    my @result;
    foreach my $tag (@{$tags}) {
        push(@result, $self -> {"template"} -> load_template("view/tag.tem",
                                                             {
                                                                 "%(name)s"   => $tag -> {"name"},
                                                                 "%(color)s"  => $tag -> {"color"},
                                                                 "%(bgcol)s"  => $tag -> {"background"},
                                                                 "%(faicon)s" => $tag -> {"fa-icon"}
                                                             }));
    }

    return join("", @result);
}


## @method private $ _convert_source($source)
# Replace all URLs in the specified source string with clickable links.
#
# @param source The source string to replace URLs in.
# @return The processed source string.
sub _convert_source {
    my $self   = shift;
    my $source = shift;

    my $match = $RE{URI}{HTTP}{-scheme => qr(https?)};
    $source =~ s|($match)|<a href="$1">$1</a>|gi;

    return $source;
}


## @method private $ _generate_view($rid)
# Generate a page containing the recipe identified by the specified ID.
#
# @param rid The ID of the recipe to fetch the data for
# @return An array containing the page title, content, extra header data, and
#         extra javascript content.
sub _generate_view {
    my $self = shift;
    my $rid  = shift;

    # If the rid is not numeric, assume it's a name and convert
    $rid = $self -> _resolve_recipe_name($rid);
    return $self -> _fatal_error("{L_VIEW_ERROR_NORECIPE}")
        unless($rid);

    # Try to fetch the data.
    my $recipe = $self -> {"system"} -> {"recipe"} -> get_recipe($rid);

    # Stop here if there's no recipe data available...
    return $self -> _fatal_error("{L_VIEW_ERROR_NORECIPE}")
        unless($recipe && $recipe -> {"id"});

    # convert various bits to blocks of HTML
    my $ingreds = $self -> _generate_ingredients($recipe -> {"ingredients"});
    my $tags    = $self -> _generate_tags($recipe -> {"tags"});
    my $source  = $self -> _convert_source($recipe -> {"source"});
    my $title   = $recipe -> {"name"};

    my $state    = $self -> check_permission('recipe.edit') ? "enabled" : "disabled";
    my $controls = $self -> {"template"} -> load_template("view/controls-$state.tem",
                                                       {
                                                           "%(url-edit)s"   => $self -> build_url(block    => "edit",
                                                                                                  pathinfo => [ $recipe -> {"id"} ]),
                                                           "%(url-delete)s" => $self -> build_url(block    => "delete",
                                                                                                  pathinfo => [ $recipe -> {"id"} ]),
                                                       });

    my $preptime  = $recipe -> {"preptime"} ? $self -> {"template"} -> humanise_seconds($recipe -> {"preptime"} * 60)
                                            : "{L_VIEW_NOTSET}";
    my $cooktime  = $recipe -> {"cooktime"} ? $self -> {"template"} -> humanise_seconds($recipe -> {"cooktime"} * 60)
                                            : "{L_VIEW_NOTSET}";

    my $totaltime = $recipe -> {"preptime"} + $recipe -> {"cooktime"};
    my $timereq   = $totaltime ? $self -> {"template"} -> humanise_seconds($totaltime * 60)
                               : "{L_VIEW_NOTSET}";

    # Mark the recipe as viewed
    $self -> {"system"} -> {"recipe"} -> set_viewed($rid, $self -> {"session"} -> get_session_userid());
    $self -> log("recipe:view", "Recipe $rid viewed by user ".$self -> {"session"} -> get_session_userid());

    # and build the page itself
    my $body  = $self -> {"template"} -> load_template("view/content.tem",
                                                       {
                                                           "%(name)s"        => $title,
                                                           "%(source)s"      => $source,
                                                           "%(yield)s"       => $recipe -> {"yield"},
                                                           "%(prepinfo)s"    => $recipe -> {"prepinfo"},
                                                           "%(preptime)s"    => $preptime,
                                                           "%(cooktime)s"    => $cooktime,
                                                           "%(timereq)s"     => $timereq,
                                                           "%(temp)s"        => $recipe -> {"temp"} ? $recipe -> {"temp"} : "",
                                                           "%(temptype)s"    => $recipe -> {"temptype"} // "",
                                                           "%(type)s"        => $recipe -> {"type"},
                                                           "%(status)s"      => $recipe -> {"status"},
                                                           "%(tags)s"        => $tags,
                                                           "%(ingredients)s" => $ingreds,
                                                           "%(method)s"      => $recipe -> {"method"},
                                                           "%(notes)s"       => $recipe -> {"notes"},
                                                           "%(controls)s"    => $controls
                                                       });

    return ($title,
            $body,
            $self -> {"template"} -> load_template("view/extrahead.tem"),
            "");
}


# ============================================================================
#  UI handler/dispatcher functions

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

    # We need to determine what the page title should be, and the content to shove in it...
    my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");
    my ($title, $body, $extrahead, $extrajs) = $self -> _generate_view($pathinfo[0]);

    # Done generating the page content, return the filled in page template
    return $self -> generate_orb_page(title     => $title,
                                      content   => $body,
                                      extrahead => $extrahead,
                                      extrajs   => $extrajs,
                                      active    => substr($title, 0, 1),
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