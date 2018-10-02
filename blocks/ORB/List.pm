## @file
# This file contains the implementation of the list page.
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
package ORB::List;

use strict;
use parent qw(ORB); # This class extends the ORB block class
use experimental qw(smartmatch);
use v5.14;


## @method private % _build_tag($tag)
# Given a reference to a hash containing tag data, generate HTML to
# represent the tag
#
# @param tag A reference to a tag hash
# @return A string representing the tag
sub _build_tag {
    my $self = shift;
    my $tag  = shift;

    return $self -> {"template"} -> load_template("list/tag.tem", { "%(name)s"   => $tag -> {"name"},
                                                                    "%(color)s"  => $tag -> {"color"},
                                                                    "%(bgcol)s"  => $tag -> {"background"},
                                                                    "%(faicon)s" => $tag -> {"fa-icon"}
                                                  });
}


## @method private % _build_recipe($recipe)
# Given a reference to a hash containing recipe data, generate HTML to
# represent the recipe
#
# @param recipe A reference to a recipe hash
# @return A string representing the recipe
sub _build_recipe {
    my $self   = shift;
    my $recipe = shift;

    my $temp = "";

    # If a temperature has been specified, it needs including in the output
    if($recipe -> {"temp"} && $recipe -> {"temptype"} ne "N/A") {
        $temp = $self -> {"template"} -> load_template("list/temp.tem",
                                                       { "%(temp)s" => $recipe -> {"temp"},
                                                         "%(temptype)s" => $recipe -> {"temptype"}
                                                       });
    }

    # Access to recipe controls is managed by metadata contexts
    my $controls = "";
    if($self -> check_permission("recipe.edit", $recipe -> {"metadata_id"})) {
        $controls .= $self -> {"template"} -> load_template("list/controls.tem",
                                                            { "%(url-edit)s"   => $self -> build_url(block => "edit", pathinfo => [ $recipe -> {"id"}  ]),
                                                              "%(url-clone)s"  => $self -> build_url(block => "edit", pathinfo => [ "clone", $recipe -> {"id"} ]),
                                                              "%(url-delete)s" => $self -> build_url(block => "edit", pathinfo => [ "delete", $recipe -> {"id"}]),
                                                            });
    }

    my $time = (($recipe -> {"preptime"} // 0) +
                ($recipe -> {"cooktime"} // 0) ) * 60;

    return $self -> {"template"} -> load_template("list/recipe.tem",
                                                  { "%(id)s"       => $recipe -> {"id"},
                                                    "%(url-view)s" => $self -> build_url(block    => "view",
                                                                                         pathinfo => [ $recipe -> {"id"} ]),
                                                    "%(name)s"     => $recipe -> {"name"},
                                                    "%(type)s"     => $recipe -> {"type"},
                                                    "%(status)s"   => $recipe -> {"status"},
                                                    "%(time)s"     => $self -> {"template"} -> humanise_seconds($time, 1),
                                                    "%(temp)s"     => $temp,
                                                    "%(tags)s"     => join("", map { $self -> _build_tag($_) } @{$recipe -> {"tags"}}),
                                                    "%(controls)s" => $controls,
                                                  });
}


## @method private $ _generate_list($mode)
# Generate the list page. This will create a page containing a list
# of recipies based on the specified mode.
#
# @return An array of two values containing the page title and content.
sub _generate_list {
    my $self = shift;
    my $mode = shift;

    # Pull a (hopefully) filtered list of recipes from the database
    my $recipes = $self -> {"system"} -> {"recipe"} -> get_recipe_list($mode)
        or $self -> generate_errorbox(message => $self -> {"system"} -> {"recipe"} -> errstr());

    # And build the template fragments from that list
    return ($self -> {"template"} -> replace_langvar("LIST_TITLE", { "%(page)s" => uc($mode // "All") }),
            $self -> {"template"} -> load_template("list/content.tem",
                                                   { "%(page)s"     => uc($mode // "All"),
                                                     "%(recipes)s"  => join("", map { $self -> _build_recipe($_) } @{$recipes}),
                                                   }),
            $self -> {"template"} -> load_template("list/extrahead.tem"),
            $self -> {"template"} -> load_template("list/extrajs.tem"),
            uc($mode // "All")
        );
}


# ============================================================================
#  UI handler/dispatcher functions

## @method private $ _dispatch_ui()
# Implements the core behaviour dispatcher for non-api functions. This will
# inspect the state of the pathinfo and invoke the appropriate handler
# function to generate content for the user.
#
# @return A string containing the page HTML.
sub _dispatch_ui {
    my $self = shift;

    # We need to determine what the page title should be, and the content to shove in it...
    my ($title, $body, $extrahead, $extrajs, $page) = ("", "", "", "", "all");

    if($self -> check_permission("recipe.view")) {
        my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");

        # If the pathinfo contains a recognised page character, use that
        if(defined($pathinfo[0]) && $pathinfo[0] =~ /^[0a-zA-Z\$]$/) {
            ($title, $body, $extrahead, $extrajs, $page) = $self -> _generate_list($pathinfo[0]);

            # If th euser has requested all recipes, do no filtering
        } elsif($pathinfo[0] && lc($pathinfo[0]) eq "all") {
            ($title, $body, $extrahead, $extrajs, $page) = $self -> _generate_list();

            # Otherwise fall back on the default of 'A' recipes
        } else {
            ($title, $body, $extrahead, $extrajs, $page) = $self -> _generate_list('A');
        }

    } else {
        ($title, $body) = $self -> generate_errorbox(message => "{L_PERMISSION_FAILED_SUMMARY}");
    }

    # Done generating the page content, return the filled in page template
    return $self -> generate_orb_page(title     => $title,
                                      content   => $body,
                                      extrahead => $extrahead,
                                      extrajs   => $extrajs,
                                      active    => $page,
                                      doclink   => 'list');
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
