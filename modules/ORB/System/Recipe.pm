## @file
# This file contains the implementation of the Recipe model.
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class Recipe
# +------------+--------------------------------+------+-----+---------+----------------+
# | Field      | Type                           | Null | Key | Default | Extra          |
# +------------+--------------------------------+------+-----+---------+----------------+
# | id         | int(10) unsigned               | NO   | PRI | NULL    | auto_increment |
# | name       | varchar(80)                    | NO   | UNI | NULL    |                |
# | source     | varchar(255)                   | NO   |     | NULL    |                |
# | timereq    | varchar(255)                   | NO   |     | NULL    |                |
# | timemins   | int(10) unsigned               | NO   | MUL | NULL    |                |
# | yield      | varchar(80)                    | NO   |     | NULL    |                |
# | temp       | smallint(5) unsigned           | YES  |     | NULL    |                |
# | temptype   | enum('C','F','Gas mark','N/A') | NO   |     | NULL    |                |
# | method     | text                           | NO   |     | NULL    |                |
# | notes      | text                           | NO   |     | NULL    |                |
# | type_id    | int(10) unsigned               | NO   | MUL | NULL    |                |
# | status_id  | int(10) unsigned               | NO   | MUL | NULL    |                |
# | creator_id | int(10) unsigned               | NO   |     | NULL    |                |
# | created    | int(10) unsigned               | NO   | MUL | NULL    |                |
# | updater_id | int(10) unsigned               | NO   |     | NULL    |                |
# | updated    | int(10) unsigned               | NO   |     | NULL    |                |
# | viewed     | int(10) unsigned               | NO   |     | NULL    |                |
# +------------+--------------------------------+------+-----+---------+----------------+

# NOTE: ADD FIELDS: parent (int 10), metadata_id (int 10), remove update*,
# NOTE: Use status field for marking as edited?

# +-----------+------------------+------+-----+---------+----------------+
# | Field     | Type             | Null | Key | Default | Extra          |
# +-----------+------------------+------+-----+---------+----------------+
# | id        | int(10) unsigned | NO   | PRI | NULL    | auto_increment |
# | recipe_id | int(10) unsigned | NO   | MUL | NULL    |                |
# | unit_id   | int(10) unsigned | YES  |     | NULL    |                |
# | prep_id   | int(10) unsigned | YES  |     | NULL    |                |
# | ingred_id | int(10) unsigned | YES  |     | NULL    |                |
# | quantity  | varchar(8)       | YES  |     | NULL    |                |
# | notes     | varchar(255)     | YES  |     | NULL    |                |
# | separator | varchar(255)     | YES  |     | NULL    |                |
# +-----------+------------------+------+-----+---------+----------------+
#
#

package ORB::System::Recipe;

use strict;
use parent qw(Webperl::SystemModule);
use v5.14;

use Webperl::Utils qw(hash_or_hashref);


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Create a new Recipe object to manage recipe creation and management.
# The minimum values you need to provide are:
#
# - `dbh`          - The database handle to use for queries.
# - `settings`     - The system settings object
# - `logger`       - The system logger object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Recipe object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);

    return $self
}


# ============================================================================
#  Recipe creation and deletion

## @method $ create(%args)
#
#
sub create {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();


}



## @method private $ _add_recipe_ingredients($recipeid, $ingredients)
# Add the specified ingredients to the recipe list for the specified recipe. This goes through
# the array of ingredients and adds each entry to the ingredient list for the specified recipe,
#
# @param recipeid    The id of the recipe to add the ingredients to.
# @param ingredients A reference to an array of ingredient specifications (quantity, units, ingredient)
# @return true on success, undef on error
sub _add_recipe_ingredients {
    my $self        = shift;
    my $recipeid    = shift;
    my $ingredients = shift;

    # Prepare the add query to make work easier later
    my $addh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"recipeing"}."`
                                            (`recipe_id`, `unit_id`, `prep_id`, `ingred_id`, `quantity`, `notes`, `separator`)
                                            VALUES(?, ?, ?, ?, ?, ?, ?)");

    # Now go through each of the ingredients
    foreach my $ingred (@{$ingredients}) {
        # If the units are 'Separator', we're actually adding a separator title rather than an ingredient
        if($ingred -> {"units"} eq "Separator") {
            $addh -> execute($recipeid, undef, undef, undef, undef, undef, $ingred -> {"name"})
                or return $self -> self_error("Error adding separator '".$ingred -> {"name"}."': ".$self -> {"dbh"} -> errstr());

        # Otherwise, it's a real ingredient, so we need to do the more complex work
        } else {
            # obtain the ingredient id
            my $ingid = $self -> {"ingredient"} -> get_ingred_id($ingred -> {"name"})
                or return $self -> self_error("Unable to get ingreditent ID for '".$ingred -> {"name"}."': ".$self -> {"ingredient"} -> errstr());

            # If we have an ID we can add the ingredient.
            $addh -> execute($recipeid, $ingred -> {"quant"}, $ingred -> {"units"}, $ingred -> {"prepid"}, $ingid, $ingred -> {"notes"}, undef)
                or return $self -> self_error("Unable to add ingredient '".$ingred -> {"name"}."' to recipe '$recipeid': ".$self -> {"dbh"} -> errstr());

            # And increase the ingredient refcount
            $self -> {"ingredient"} -> increase_refcount_byid($ingid);
        }
    }

    # Get here and all worked out okay
    return 1;
}


## @method $ add_recipe_tags($recipeid, $tags, $userid)
# Add the specified tags to a recipe, setting the provided userid as the creator for new tags.
#
# @param recipeid  The id of the recipe to add the tags to.
# @param tags      A string containing a comma-delimited list of tags.
# @param userid    The id of the user creating the recipe.
sub add_recipe_tags {
    my $self     = shift;
    my $recipeid = shift;
    my $tags     = shift;
    my $userid   = shift;

    # Bomb immediately if the tags list is empty
    return undef if(!$tags || length($tags) == 0);

    # Split the tag after removing any extraneous whitespace between tags
    $tags =~ s/\s*,\s*/,/g;
    my @values = split(/,/, $tags);

    # Now we prepare the tag insert query for action
    my $addh = $self -> {"dbh"} -> prepare("INSERT INTO ".$self -> {"settings"} -> {"database"} -> {"recipetags"}."
                                            (`recipe_id`, `tag_id`)
                                            VALUES(?, ?)");

    # Go through each tag, adding it
    foreach my $tag (@values) {
        # Try to get the tag id
        my $tagid = $self -> {"ingredient"} -> get_tag_id($tag, $userid)
            or return $self -> self_error("Unable to obtain ID for tag '$tag'");

        $addh -> execute($recipeid, $tagid)
            or return $self -> self_error("Tag association failed: ".$self -> {"dbh"} -> errstr);
    }

    return 1;
}



1;
