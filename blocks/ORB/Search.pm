## @file
# This file contains the implementation of the search page.
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
package ORB::Search;

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

    return $self -> {"template"} -> load_template("search/tag.tem", { "%(name)s"   => $tag -> {"name"},
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
        $temp = $self -> {"template"} -> load_template("search/temp.tem",
                                                       { "%(temp)s" => $recipe -> {"temp"},
                                                         "%(temptype)s" => $recipe -> {"temptype"}
                                                       });
    }

    # Access to recipe controls is managed by metadata contexts
    my $controls = "";
    if($self -> check_permission("recipe.edit", $recipe -> {"metadata_id"})) {
        $controls .= $self -> {"template"} -> load_template("search/controls.tem",
                                                            { "%(url-edit)s"   => $self -> build_url(block => "edit", pathinfo => [ $recipe -> {"id"}  ]),
                                                              "%(url-clone)s"  => $self -> build_url(block => "edit", pathinfo => [ "clone", $recipe -> {"id"} ]),
                                                              "%(url-delete)s" => $self -> build_url(block => "edit", pathinfo => [ "delete", $recipe -> {"id"}]),
                                                            });
    }

    my $time = (($recipe -> {"preptime"} // 0) +
                ($recipe -> {"cooktime"} // 0) ) * 60;

    return $self -> {"template"} -> load_template("search/recipe.tem",
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



sub _build_search_results {
    my $self     = shift;
    my $term     = shift;
    my $origonly = shift // 1;

    my $recipes = $self -> {"system"} -> {"recipe"} -> find(name        => $term,
                                                            method      => $term,
                                                            ingredients => [ '%'.$term.'%' ],
                                                            ingredmatch => 'any',
                                                            tags        => [ '%'.$term.'%' ],
                                                            tagmatch    => 'any',
                                                            limit       => 50,
                                                            searchmode  => 'any',
                                                            original    => $origonly);

    # And build the template fragments from that list
    return ($self -> {"template"} -> replace_langvar("SEARCH_TITLE", { "%(page)s" => "ALL" }),
            $self -> {"template"} -> load_template("search/content.tem",
                                                   { "%(page)s"     => "ALL",
                                                     "%(recipes)s"  => join("", map { $self -> _build_recipe($_) } @{$recipes}),
                                                   }),
            $self -> {"template"} -> load_template("search/extrahead.tem"),
            $self -> {"template"} -> load_template("search/extrajs.tem")
        );

}


sub _generate_search {
    my $self = shift;

    my ($term, $error) = $self -> validate_string('search',
                                                  {
                                                      required => 0,
                                                      default  => undef,
                                                      nicename => "{L_SEARCH_SEARCH}",
                                                      minlen   => 4
                                                  });

    return $self -> _build_search_results($term)
        if($term);

    return $self -> _build_search_form($error);
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

    return ("{L_SEARCH_ERROR_FATAL}",
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

    my ($title, $body, $extrahead, $extrajs) = $self -> _generate_search();

    # Done generating the page content, return the filled in page template
    return $self -> generate_orb_page(title     => $title,
                                      content   => $body,
                                      extrahead => $extrahead,
                                      extrajs   => $extrajs,
                                      active    => 'ALL',
                                      doclink   => 'search');
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