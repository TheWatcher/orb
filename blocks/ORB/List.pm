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
use Data::Dumper;
## @method private % _build_tag($tag)
# Given a reference to a hash containing tag data, generate HTML to
# represent the tag
#
# @param tag A reference to a tag hash
# @return A string representing the tag
sub _build_tag {
    my $self = shift;
    my $tag  = shift;

    return $self -> {"template"} -> load_template("list/tag.tem", { "%(name)s" => $tag -> {"name"},
                                                                    "%(color)s" => $tag -> {"color"},
                                                                    "%(bgcol)s" => $tag -> {"background"},
                                                                    "%(faicon)s" => $tag -> {"fa-icon"}
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

    my $recipes = $self -> {"system"} -> {"recipe"} -> get_recipe_list($mode)
        or $self -> generate_errorbox(message => $self -> {"system"} -> {"recipe"} -> errstr());

    my @list;
    foreach my $recipe (@{$recipes}) {
        my $temp = "";

        if($recipe -> {"temp"} && $recipe -> {"temptype"} ne "N/A") {
            $temp = $self -> {"template"} -> load_template("list/temp.tem", { "%(temp)s" => $recipe -> {"temp"},
                                                                              "%(temptype)s" => $recipe -> {"temptype"}
                                                           });
        }

        my $controls = "";
        if($self -> check_permission("recipe.edit", $recipe -> {"metadata_id"})) {
            $controls .= $self -> {"template"} -> load_template("list/recipe.tem",
                                                                { "%(url-edit)s" => $self -> build_url(block => "edit", pathinfo => [ $recipe -> {"id"}  ]),
                                                                  "%(url-edit)s" => $self -> build_url(block => "edit", pathinfo => [ "clone", $recipe -> {"id"} ]),
                                                                  "%(url-edit)s" => $self -> build_url(block => "edit", pathinfo => [ "delete", $recipe -> {"id"}]),
                                                                });
        }

        push(@list, $self -> {"template"} -> load_template("list/recipe.tem",
                                                           { "%(id)s"       => $recipe -> {"id"},
                                                             "%(url-view)s" => $self -> build_url(block    => "view",
                                                                                                  pathinfo => [ $recipe -> {"id"} ]),
                                                             "%(name)s"     => $recipe -> {"name"},
                                                             "%(type)s"     => $recipe -> {"type"},
                                                             "%(status)s"   => $recipe -> {"status"},
                                                             "%(time)s"     => $self -> {"template"} -> humanise_seconds($recipe -> {"timemins"} * 60, 1),
                                                             "%(temp)s"     => $temp,
                                                             "%(tags)s"     => join("", map { $self -> _build_tag($_) } @{$recipe -> {"tags"}}),
                                                             "%(controls)s" => $controls,
                                                           }));
    }

    return ($self -> {"template"} -> replace_langvar("LIST_TITLE", { "%(page)s" => uc($mode // "All") }),
            $self -> {"template"} -> load_template("list/content.tem", {"%(pagemenu)s" => $self -> pagemenu($mode),
                                                                        "%(page)s"     => uc($mode // "All"),
                                                                        "%(recipes)s"  => join("", @list),
                                                   }),
            $self -> {"template"} -> load_template("list/extrahead.tem"),
            $self -> {"template"} -> load_template("list/extrajs.tem"),
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
    my ($title, $body, $extrahead, $extrajs) = ("", "", "", "");
    my @pathinfo = $self -> {"cgi"} -> multi_param("pathinfo");

    print STDERR "Mode: ".$pathinfo[0]."\n";
    if(defined($pathinfo[0]) && $pathinfo[0] =~ /^[0a-zA-Z\$]$/) {
        ($title, $body, $extrahead, $extrajs) = $self -> _generate_list($pathinfo[0]);
    } elsif($pathinfo[0] && lc($pathinfo[0]) eq "all") {
        ($title, $body, $extrahead, $extrajs) = $self -> _generate_list();
    } else {
        ($title, $body, $extrahead, $extrajs) = $self -> _generate_list('A');
    }

    # Done generating the page content, return the filled in page template
    return $self -> generate_orb_page(title     => $title,
                                      content   => $body,
                                      extrahead => $extrahead,
                                      extrajs   => $extrajs,
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