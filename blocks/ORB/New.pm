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
use parent qw(ORB); # This class extends the ORB block class
use experimental qw(smartmatch);
use v5.14;

# How many ingredient rows should appear in the empty form?
use constant DEFAULT_INGREDIENT_COUNT => 5;


## @method private $ _build_timereq($seconds)
# Given a time requirement in seconds, generate a string representing
# the time required in the form "X days, Y hours and Z minues",
# optionally dropping parts of the string depending on whether
# X, Y, or Z are zero.
#
# @param seconds The number of seconds required to make the recipe.
# @return A string representing the seconds.
sub _build_timereq {
    my $self    = shift;
    my $seconds = shift;

    my $days  = int($seconds / (24 * 60 * 60));
    my $hours = ($seconds / (60 * 60)) % 24;
    my $mins  = ($seconds / 60) % 60;

    # localisation needed...
    my @parts = ();
    push(@parts, "$days days") if($days);
    push(@parts, "$hours hours") if($hours);
    push(@parts, "$mins minutes") if($mins);

    my $count = scalar(@parts);
    if($count == 3) {
        return $parts[0].", ".$parts[1]." and ".$parts[2];
    } elsif($count == 2) {
        return $parts[0]." and ".$parts[1];
    } elsif($count == 1) {
        return $parts[0];
    }

    return "";
}


sub _build_temptypes {
    my $self    = shift;
    my $default = shift;

    # Supported types are in the column enum list
    my $tempenum  = $self -> get_enum_values($self -> {"settings"} -> {"database"} -> {"recipes"}, "temptype");
    return $tempenum
        unless(ref($tempenum) eq "ARRAY");

    # convert to something build_optionlist will understand
    map { $_ = { name  => $_, value => $_ } } @{$tempenum};

    return $self -> {"template"} -> build_optionlist($tempenum, $default);
}


sub _get_units {
    my $self = shift;

    return $self -> {"units"}
        if($self -> {"units"});

    $self -> {"units"} = [
        { value => "None", name => "None" },
        @{ $self -> {"system"} -> {"entities"} -> {"units"}  -> as_options(1) }
    ];

    return $self -> {"units"};
}


sub _build_ingredients {
    my $self  = shift;
    my $args  = shift;
    my $units = shift;
    my $preps = shift;

    my @ingreds = ();

    # If any ingredients are present in the argument list, push them into templated strings
    if($args -> {"ingredients"} && scalar(@{$args -> {"ingredients"}})) {
        foreach my $ingred (@{$args -> {"ingredients"}}) {
            # Ensure we never try to deal with undef elements in the array
            next unless($ingred);

            # Which template to use depends on whether this is a separator
            my $template = $ingred -> {"separator"} ? "new/separator.tem" : "new/ingredient.tem";

            my $unitopts = $self -> {"template"} -> build_optionlist($units, $args -> {"units"});
            my $prepopts = $self -> {"template"} -> build_optionlist($preps, $args -> {"prep"});

            push(@ingreds,
                 $self -> {"template"} -> load_template($template,
                                                        { "%(quantity)s" => $ingred -> {"quantity"},
                                                          "%(name)s"     => $ingred -> {"name"},
                                                          "%(notes)s"    => $ingred -> {"notes"},
                                                          "%(units)s"    => $unitopts,
                                                          "%(preps)s"    => $prepopts,
                                                        }));
        }

    # if the ingredient list is empty, generate some empties
    } else {
        # Only need to calculate these once for the empty ingredients
        my $unitopts = $self -> {"template"} -> build_optionlist($units);
        my $prepopts = $self -> {"template"} -> build_optionlist($preps);

        for(my $i = 0; $i < DEFAULT_INGREDIENT_COUNT; ++$i) {
            push(@ingreds,
                 $self -> {"template"} -> load_template("new/ingredient.tem",
                                                        { "%(quantity)s" => "",
                                                          "%(name)s"     => "",
                                                          "%(notes)s"    => "",
                                                          "%(units)s"    => $unitopts,
                                                          "%(preps)s"    => $prepopts,
                                                        }));
        }
    }

    return join("", @ingreds);
}


sub _generate_new {
    my $self = shift;
    my ($args, $errors);

    if($errors) {
        $self -> log("new", "Errors detected in addition: $errors");

        my $errorlist = $self -> {"template"} -> load_template("error/error_list.tem", {"%(message)s"  => "{L_NEW_ERRORS}",
                                                                                        "%(errors)s" => $errors });
        $errors = $self -> {"template"} -> load_template("error/page_error.tem", { "%(message)s" => $errorlist });
    }

    # Prebuild arrays for units and prep methods
    my $units = $self -> _get_units();
    my $preps = $self -> {"system"} -> {"entities"} -> {"prep"} -> as_options(1);

    # And convert them to optionlists for the later template call
    my $unitopts   = $self -> {"template"} -> build_optionlist($units);
    my $prepopts   = $self -> {"template"} -> build_optionlist($preps);

    # Build the list of ingredients
    my $ingredients = $self -> _build_ingredients($args, $units, $preps);

    # Build up the type and status data
    my $typeopts   = $self -> {"template"} -> build_optionlist($self -> {"system"} -> {"entities"} -> {"types"}  -> as_options(),
                                                               $args -> {"type"});

    my $statusopts = $self -> {"template"} -> build_optionlist($self -> {"system"} -> {"entities"} -> {"states"} -> as_options(0, visible => {value => 1}),
                                                               $args -> {"status"});

    # Convert the time fields
    my ($timemins, $timesecs) = ("", 0);
    if($args -> {"timemins"}) {
        $timesecs = $args -> {"timemins"} * 60;
        $timemins = $self -> _build_timereq($timesecs);
    }

    # And squirt out the page content
    my $body  = $self -> {"template"} -> load_template("new/content.tem",
                                                       {
                                                           "%(errors)s"    => $errors,
                                                           "%(name)s"      => $args -> {"name"} // "",
                                                           "%(source)s"    => $args -> {"source"} // "",
                                                           "%(yield)s"     => $args -> {"yield"} // "",
                                                           "%(timereq)s"   => $args -> {"timereq"} // "",
                                                           "%(timemins)s"  => $timemins,
                                                           "%(timesecs)s"  => $timesecs,
                                                           "%(temp)s"      => $args -> {"temp"} // "",
                                                           "%(temptypes)s" => $self -> _build_temptypes($args -> {"temptype"}),
                                                           "%(types)s"     => $typeopts,
                                                           "%(units)s"     => $unitopts,
                                                           "%(preps)s"     => $prepopts,
                                                           "%(status)s"    => $statusopts,
                                                           "%(ingreds)s"   => $ingredients,
                                                           "%(method)s"    => $args -> {"method"} // "",
                                                           "%(notes)s"     => $args -> {"notes"} // "",
                                                       });

    return ($self -> {"template"} -> replace_langvar("NEW_TITLE"),
            $body,
            $self -> {"template"} -> load_template("new/extrahead.tem"),
            $self -> {"template"} -> load_template("new/extrajs.tem"));
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