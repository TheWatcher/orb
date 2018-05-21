## @file
# This file contains the implementation of the summary page.
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
package ORB::Summary;

use strict;
use parent qw(ORB); # This class extends the ORB block class
use experimental qw(smartmatch);
use v5.14;


## @method private $ _build_summary_list($field)
# Build a list of recipes ordered by the specified field. This will
# generate a string containing one or more table rows of data for
# recipes ordered by the specified field.
#
# @param field The field to sort data on; should be 'added', 'updated',
#              or 'viewed'
# @return A string containing the table rows for the recipes.
sub _build_summary_list {
    my $self  = shift;
    my $field = shift;

    # First fetch the list of matching recipes
    my $recipes = $self -> {"system"} -> {"recipe"} -> find(limit => $self -> {"settings"} -> {"config"} -> {"Summary:limit"} // 5,
                                                            order => $field);
    return ""
        unless($recipes && scalar(@{$recipes}));

    my $list = "";
    foreach my $recipe (@{$recipes}) {
        my $url = $self -> build_url(block    => "view",
                                     pathinfo => [ $recipe -> {"id"} ]);

        $list .= $self -> {"template"} -> load_template("summary/row.tem", { "%(url)s"  => $url,
                                                                             "%(name)s" => $recipe -> {"name"},
                                                                             "%(type)s" => $recipe -> {"type"} });
    }

    return $list;
}


## @method private $ _generate_summaries()
# Generate the summary page. This will create a page containing summary
# tables showing the most recently viewed, added, or updated recipes.
#
# @return An array of two values containing the page title and content.
sub _generate_summaries {
    my $self = shift;

    return ("{L_SUMMARY_TITLE}",
            $self -> {"template"} -> load_template("summary/content.tem", {"%(added)s"    => $self -> _build_summary_list("added"),
                                                                           "%(viewed)s"   => $self -> _build_summary_list("viewed"),
                                                                           "%(updated)s"  => $self -> _build_summary_list("updated"),
                                                   })
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

    given($pathinfo[0]) {
        default{ ($title, $body, $extrahead, $extrajs) = $self -> _generate_summaries(); }
    }

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