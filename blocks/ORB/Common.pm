## @file
# This file contains functions that can be common to the New and Edit pages
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
package ORB::Common;

use strict;
use parent qw(ORB); # This class extends the ORB block class
use experimental qw(smartmatch);
use v5.14;
use JSON;

# How many ingredient rows should appear in the empty form?
use constant DEFAULT_INGREDIENT_COUNT => 5;


# ============================================================================
#  Page generation support functions

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

    # FIXME: localisation needed?
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


## @method private $ _build_temptypes()
# Generate a list of temperature types supported by the system in a form
# suitable for using during validation and as an argument to build_optionlist()
#
# @return A reference to an array of {name => "", value => ""} hashes
#         representing the supported temperature types
sub _build_temptypes {
    my $self    = shift;

    return $self -> {"temptypes"}
        if($self -> {"temptypes"});

    # Supported types are in the column enum list
    my $tempenum  = $self -> get_enum_values($self -> {"settings"} -> {"database"} -> {"recipes"}, "temptype");
    return $tempenum
        unless(ref($tempenum) eq "ARRAY");

    # convert to something build_optionlist will understand
    map { $_ = { name  => $_, value => $_ } } @{$tempenum};

    $self -> {"temptypes"} = $tempenum;

    return $self -> {"temptypes"};
}


## @method private $ _get_units()
# Generate the list of supported units in the system. This creates a
# units list (and caches it) that can be used for validation and
# generating the unit options in the ingredients list.
#
# @return A reference to an array of {name => "", value => ""} hashes
#         representing the supported units
sub _get_units {
    my $self = shift;

    return $self -> {"units"}
        if($self -> {"units"});

    $self -> {"units"} = [
        { value => "None", name => "- Units -" },
        @{ $self -> {"system"} -> {"entities"} -> {"units"}  -> as_options(1) }
    ];

    return $self -> {"units"};
}


## @method private $ _get_prepmethods()
# Generate the list of supported preparation methods in the system. This
# creates a prep methods list (and caches it) that can be used for
# validation and generating the prep method options in the ingredients list.
#
# @return A reference to an array of {name => "", value => ""} hashes
#         representing the supported prep methods
sub _get_prepmethods {
    my $self = shift;

    return $self -> {"preps"}
        if($self -> {"preps"});

    $self -> {"preps"} = [
        { value => "None", name => "- Prep -" },
        @{ $self -> {"system"} -> {"entities"} -> {"prep"}  -> as_options(1) }
    ];

    return $self -> {"preps"};
}


## @method private $ _build_ingredients($args)
# Generate the list of ingredients to show in the form. If there are no
# pre-existing ingredients defined in the supplied args hash, this will
# generate DEFAULT_INGREDIENT_COUNT empty ingredients.
#
# @param args A reference to a hash of arguments including an
#             `ingredients` arrayref.
# @return A string containing the ingredients list.
sub _build_ingredients {
    my $self  = shift;
    my $args  = shift;

    my @ingreds = ();

    # Need units and prep methods for generation
    my $units = $self -> _get_units();
    my $preps = $self -> _get_prepmethods();

    # If any ingredients are present in the argument list, push them into templated strings
    if($args -> {"ingredients"} && scalar(@{$args -> {"ingredients"}})) {
        foreach my $ingred (@{$args -> {"ingredients"}}) {
            # Ensure we never try to deal with undef elements in the array
            next unless($ingred);

            # Which template to use depends on whether this is a separator
            my $template = $ingred -> {"separator"} ? "new/separator.tem" : "new/ingredient.tem";

            my $unitopts = $self -> {"template"} -> build_optionlist($units, $ingred -> {"units"});
            my $prepopts = $self -> {"template"} -> build_optionlist($preps, $ingred -> {"prep"});

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


# ============================================================================
#  Validation support


## @method private $ _validate_separator($args, $sepdata)
# Validate the values specified for a separator in the ingredient list.
#
# @param args A reference to a hash containing the validated recipe values.
# @param ingdata A reference to a hash containing the separator data to validate.
# @return The empty string on success, otherwise a string containing errors
#         encountered during validation.
sub _validate_separator {
    my $self    = shift;
    my $args    = shift;
    my $sepdata = shift;

    # check that the separator name is valid
    if($sepdata -> {"name"} =~ /$self->{formats}->{sepname}/) {
        push(@{$args -> {"ingredients"}}, { "separator" => 1,
                                            "name"      => $sepdata -> {"name"}} );
        return "";

    } else {
        return $self -> {"template"} -> load_template("error/error_item.tem",
                                                      { "%(error)s" => "{L_ERR_BADSEPNAME}" });
    }
}


## @method private $ _validate_ingredient_option($value, $name, $options)
# Validate the value specified for an option (unit or prepmethod) specified
# for an ingredient in the ingredient list.
#
# @param value   The value to validate.
# @param name    The name of the field being validated.
# @param options A reference to a list of options to validate the value against.
sub _validate_ingredient_option {
    my $self    = shift;
    my $value   = shift;
    my $name    = shift;
    my $options = shift;

    foreach my $check (@{$options}) {
        if(ref($check) eq "HASH") {
            return ($value, undef) if($check -> {"value"} eq $value);
        } else {
            return ($value, undef) if($check eq $value);
        }
    }

    return ("", $self -> {"template"} -> replace_langvar("BLOCK_VALIDATE_BADOPT", {"***field***" => $name}));
}


## @method private $ _validate_ingredient($args, $ingdata)
# Validate the values specified for an ingredient in the ingredient list.
#
# @param args    A reference to a hash containing the validated ingredient data.
# @param ingdata A reference to a hash containing the ingredient data to check.
# @return The empty string on success, otherwise a string containing errors
#         encountered during validation.
sub _validate_ingredient {
    my $self    = shift;
    my $args    = shift;
    my $ingdata = shift;
    my ($error, $errors)  = ("", "");

    # Do nothing unless something has been set for the name
    return ""
        unless($ingdata -> {"name"});

    # Start accumulating ingredient data here
    my $ingredient = {
        "separator" => 0,
        "notes"     => "",
    };

    # Quantity valid?
    if($ingdata -> {"quantity"}) {
        if($ingdata -> {"quantity"} =~ /$self->{formats}->{quantity}/) {
            $ingredient -> {"quantity"} = $ingdata -> {"quantity"};
        } else {
            $errors .= $self -> {"template"} -> load_template("error/error_item.tem",
                                                              { "%(error)s" => "{L_ERR_BADQUANTITY}" });
        }
    }

    # Name valid?
    if($ingdata -> {"name"} =~ /$self->{formats}->{ingredient}/) {
        $ingredient -> {"name"} = $ingdata -> {"name"};
    } else {
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem",
                                                          { "%(error)s" => "{L_ERR_BADINGNAME}" });
    }

    # Notes get copied, as long as they don't contain junk
    if($ingdata -> {"notes"}) {
        if($ingdata -> {"notes"} =~ /$self->{formats}->{notes}/) {
            $ingredient -> {"notes"} = $self -> {"template"} -> html_clean($ingdata -> {"notes"});
        } else {
            $errors .= $self -> {"template"} -> load_template("error/error_item.tem",
                                                              { "%(error)s" => "{L_ERR_BADNOTES}: '".$ingdata -> {"notes"}."'" });
        }
    }

    # Units and prep method are option lists, so check them
    ($ingredient -> {"units"}, $error) = $self -> _validate_ingredient_option($ingdata -> {"units"},
                                                                              "{L_RECIPE_UNITS}",
                                                                              $self -> _get_units());
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    ($ingredient -> {"prep"}, $error) = $self -> _validate_ingredient_option($ingdata -> {"prep"},
                                                                              "{L_RECIPE_PREP}",
                                                                              $self -> _get_prepmethods());
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # Store everything that passed validation
    push(@{$args -> {"ingredients"}}, $ingredient);

    return $errors;
}


## @method private $ _validate_ingredients($args)
# Validate the values supplied for the recipe's ingredients.
#
# @param args A reference to the hash to store the ingredients data in.
# @return An empty string on success, otherwise a string containing one or
#         more error messages wrapped in <li></li>
sub _validate_ingredients {
    my $self = shift;
    my $args = shift;
    my ($error, $errors) = ( "", "");

    ($args -> {"ingdata"}, $error) = $self -> validate_string("ingdata", { required   => 1,
                                                                           default    => "",
                                                                           nicename   => "{L_RECIPE_INGREDIENTS}",
                                                                           encode     => 0,
                                                             });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    my $ingdata = eval { decode_json($args -> {"ingdata"}) };
    return $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => "{L_ERR_JSONFORMAT}: $@" })
        if($@);

    foreach my $ingred (@{$ingdata -> {"ingredients"}}) {
        if($ingred -> {"separator"}) {
            $errors .= $self -> _validate_separator($args, $ingred);
        } else {
            $errors .= $self -> _validate_ingredient($args, $ingred);
        }
    }

    return $errors;
}


## @method private $ _validate_recipe($temptypes)
# Validate the values supplied by the user for the recipe. If the values are
# all correct, this will create a new recipe before returning.
#
# @return An array of two values: the first is a reference to a hash of
#         valid or default recipe field values, the second is a string
#         containing error messages, or the empty string if everything
#         passed validation.
sub _validate_recipe {
    my $self      = shift;
    my ($args, $error, $errors) = ( {}, "", "" );

    # <label>{L_RECIPE_NAME}
    ($args -> {"name"}, $error) = $self -> validate_string("name", { required   => 1,
                                                                     default    => "",
                                                                     minlen     => 4,
                                                                     maxlen     => 80,
                                                                     nicename   => "{L_RECIPE_NAME}",
                                                                     formattest => $self -> {"formats"} -> {"recipename"},
                                                                     formatdesc => "{L_ERR_NAMEFORMAT}"
                                                           });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # <label>{L_RECIPE_SOURCE}
    ($args -> {"source"}, $error) = $self -> validate_string("source", { required   => 0,
                                                                         default    => "",
                                                                         maxlen     => 255,
                                                                         nicename   => "{L_RECIPE_SOURCE}"
                                                             });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # <label>{L_RECIPE_YIELD}
    ($args -> {"yield"}, $error) = $self -> validate_string("yield", { required   => 0,
                                                                       default    => "",
                                                                       maxlen     => 80,
                                                                       nicename   => "{L_RECIPE_SOURCE}"
                                                            });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # <label>{L_RECIPE_PREPINFO}
    ($args -> {"prepinfo"}, $error) = $self -> validate_string("prepinfo", { required   => 0,
                                                                             default    => "",
                                                                             maxlen     => 255,
                                                                             nicename   => "{L_RECIPE_PREPINFO}"
                                                              });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # <label>{L_RECIPE_PREPTIME}
    ($args -> {"prepsecs"}, $error) = $self -> validate_numeric("prepsecs", { required => 1,
                                                                              default  => 0,
                                                                              intonly  => 1,
                                                                              min      => 1,
                                                                              nicename => "{L_RECIPE_PREPTIME}"
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    $args -> {"preptime"} = int($args -> {"prepsecs"} / 60);

    # <label>{L_RECIPE_COOKTIME}
    ($args -> {"cooksecs"}, $error) = $self -> validate_numeric("cooksecs", { required => 1,
                                                                              default  => 0,
                                                                              intonly  => 1,
                                                                              min      => 1,
                                                                              nicename => "{L_RECIPE_COOKTIME}"
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    $args -> {"cooktime"} = int($args -> {"cooksecs"} / 60);


    # <label>{L_RECIPE_OVENTEMP}
    ($args -> {"temp"}, $error) = $self -> validate_numeric("temp", { required => 0,
                                                                      default  => 0,
                                                                      intonly  => 1,
                                                                      nicename => "{L_RECIPE_OVENTEMP}"
                                                            });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    my $temptypes = $self -> _build_temptypes();
    ($args -> {"temptype"}, $error) = $self -> validate_options("temptype", { required => 0,
                                                                              default  => "N/A",
                                                                              source   => $temptypes,
                                                                              nicename => "{L_RECIPE_OVENTEMP}"
                                                               });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);


    # <label>{L_RECIPE_TYPE}
    my $types = $self -> {"system"} -> {"entities"} -> {"types"} -> as_options(1);
    ($args -> {"type"}, $error) = $self -> validate_options("type", { required => 1,
                                                                      source   => $types,
                                                                      nicename => "{L_RECIPE_TYPE}"
                                                               });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);


    # <label>{L_RECIPE_STATUS}
    my $states = $self -> {"system"} -> {"entities"} -> {"states"} -> as_options(1, visible => {value => 1});
    ($args -> {"status"}, $error) = $self -> validate_options("status", { required => 1,
                                                                          source   => $states,
                                                                          nicename => "{L_RECIPE_STATUS}"
                                                               });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # <label>{L_RECIPE_TAGS}
    my @tags = $self -> {"cgi"} -> multi_param("tags");
    my @taglist = ();
    foreach my $tag (@tags) {
        if($tag =~ /$self->{formats}->{tags}/) {
            push(@taglist, $tag);
        } else {
            $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => "{L_ERR_TAGFORMAT}" });
        }
    }
    $args -> {"tags"} = join(",", @taglist);


    # Ingredients need to be validated in their own function because this is entirely too long already, like this line
    $errors .= $self -> _validate_ingredients($args);


     # <label>{L_RECIPE_METHOD}
    ($args -> {"method"}, $error) = $self -> validate_htmlarea("method", { required   => 1,
                                                                           default    => "",
                                                                           minlen     => 4,
                                                                           nicename   => "{L_RECIPE_METHOD}",
                                                             });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    # <label>{L_RECIPE_NOTES}
    ($args -> {"notes"}, $error) = $self -> validate_htmlarea("notes", { required   => 0,
                                                                         default    => "",
                                                                         nicename   => "{L_RECIPE_NOTES}"
                                                             });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", { "%(error)s" => $error })
        if($error);

    return ($args, $errors);
}


1;