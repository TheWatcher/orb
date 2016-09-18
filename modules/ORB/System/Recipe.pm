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
# +-------------+--------------------------------+------+-----+---------+----------------+
# | Field       | Type                           | Null | Key | Default | Extra          |
# +-------------+--------------------------------+------+-----+---------+----------------+
# | id          | int(10) unsigned               | NO   | PRI | NULL    | auto_increment |
# | prev_id     | int(11)                        | YES  |     | NULL    |                |
# | metadata_id | int(11)                        | NO   |     | NULL    |                |
# | name        | varchar(80)                    | NO   | UNI | NULL    |                |
# | method      | text                           | NO   |     | NULL    |                |
# | notes       | text                           | YES  |     | NULL    |                |
# | source      | varchar(255)                   | YES  |     | NULL    |                |
# | yield       | varchar(80)                    | NO   |     | NULL    |                |
# | timereq     | varchar(255)                   | NO   |     | NULL    |                |
# | timemins    | int(10) unsigned               | NO   | MUL | NULL    |                |
# | temptype    | enum('C','F','Gas mark','N/A') | NO   |     | NULL    |                |
# | temp        | smallint(5) unsigned           | YES  |     | NULL    |                |
# | type_id     | int(10) unsigned               | NO   | MUL | NULL    |                |
# | status_id   | int(10) unsigned               | NO   | MUL | NULL    |                |
# | creator_id  | int(10) unsigned               | NO   |     | NULL    |                |
# | created     | int(10) unsigned               | NO   | MUL | NULL    |                |
# | viewed      | int(10) unsigned               | NO   |     | NULL    |                |
# +-------------+--------------------------------+------+-----+---------+----------------+

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
# Create a new recipe in the system, or edit a recipe setting the status of
# the old version to 'edited'. The args hash can contain the following, all
# fields are required unless indicated otherwise:
#
# -      `previd`: (optional) ID of the recipe this is an edit of. If specified,
#                  the old recipe has its state set to 'edited', and the
#                  metadata context of the new recipe is created as a child of
#                  the old recipe to ensure editing works as expected.
# -        `name`: The name of the recipe
# -      `source`: (optional) Where did the recipe come from originally?
# -     `timereq`: A string describing the time required for the recipe
# -    `timemins`: How long does the recipe take in minutes, in total?
# -       `yield`: A string describing how much stuff the recipe creates
# -        `temp`: (optional) Oven preheat temperature
# -    `temptype`: The type of units used: 'C', 'F', 'Gas mark', or 'N/A'
# -      `method`: HTML text containing the recipe instructions
# -       `notes`: (optional) Additional information about the recipe
# -        `type`: The recipe type
# -      `status`: The recipe status
# -   `creatorid`: The ID of the user who created the recipe
# - `ingredients`: A reference to an array of ingredient hashes. See the
#                  documentation for _add_recipe_ingredients() for the
#                  required hash values
#
# @param args A hash, or reference to a hash, of values to use when creating
#             the new recipe.
# @return A reference to a hash containing the new recipe ID on success,
#         undef on error.
sub create {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();



    # We need a metadata context for the recipe
    my $metadataid = $self -> _create_recipe_metadata($args -> {"previd"});

    # Do the insert, and fetch the ID of the new row
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                            (`metadata_id`, `prev_id`, `name`, `source`, `timereq`, `timemins`, `yield`, `temp`, `temptype`, `method`, `notes`, `type_id`, `status_id`, `creator_id`, `created`)
                                            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, UNIX_TIMESTAMP())");
    my $result = $newh -> execute($metadataid, $args -> {"previd"}, $args -> {"name"}, $args -> {"source"}, $args -> {"timereq"}, $args -> {"timemins"}, $args -> {"yield"}, $args -> {"temp"}, $args -> {"temptype"}, $args -> {"method"}, $args -> {"notes"}, $args -> {"type_id"}, $args -> {"status_id"}, $args -> {"creatorid"});
    return $self -> self_error("Insert of recipe failed: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("No rows added when inserting recipe.") if($result eq "0E0");

    my $newid = $self -> {"dbh"} -> {"mysql_insertid"};

    return $self -> self_error("Unable to obtain id for new recipe")
        if(!$newid);

    # Attach to the metadata context as it's in use now
    $self -> {"metadata"} -> attach($metadataid)
        or return $self -> self_error("Error in metadata system: ".$self -> {"metadata"} -> errstr());


    # Add the ingredients for the recipe

}


# ==============================================================================
#  Private methods

## @method private $ _add_recipe_ingredients($recipeid, $ingredients)
# Add the specified ingredients to the recipe list for the specified recipe.
# This goes through the array of ingredients and adds each entry to the
# ingredient list for the specified recipe. The ingredients are specified
# as an array of hashrefs, each hash should contain the following keys:
#
# - `separator`: if true, the ingredient is a separator, and `name` is set
#                as the separator line title.
# - `name`: the ingredient name (or separator title if `separator` is true.
# -
#
# @param recipeid    The id of the recipe to add the ingredients to.
# @param ingredients A reference to an array of hashes containing ingredient
#                    specifications.
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

        # Handle serparators... separately
        if($ingred -> {"separator"}) {
            $addh -> execute($recipeid, undef, undef, undef, undef, undef, $ingred -> {"name"})
                or return $self -> self_error("Error adding separator '".$ingred -> {"name"}."': ".$self -> {"dbh"} -> errstr());

        # Otherwise, it's a real ingredient, so we need to do the more complex work
        } else {
            # obtain the ingredient id
            my $ingid = $self -> {"ingredients"} -> get_id($ingred -> {"name"})
                or return $self -> self_error("Unable to get ingreditent ID for '".$ingred -> {"name"}."': ".$self -> {"ingredient"} -> errstr());

            # If we have an ID we can add the ingredient.
            $addh -> execute($recipeid, $ingred -> {"quant"}, $ingred -> {"units"}, $ingred -> {"prepid"}, $ingid, $ingred -> {"notes"}, undef)
                or return $self -> self_error("Unable to add ingredient '".$ingred -> {"name"}."' to recipe '$recipeid': ".$self -> {"dbh"} -> errstr());

            # And increase the ingredient refcount
            $self -> {"system"} -> {"ingredients"} -> increase_refcount($ingid);
        }
    }

    # Get here and all worked out okay
    return 1;
}


## @method $ add_recipe_tags($recipeid, $tags)
# Add the specified tags to a recipe, setting the provided userid as the creator for new tags.
#
# @param recipeid  The id of the recipe to add the tags to.
# @param tags      A string containing a comma-delimited list of tags, or a reference to an
#                  array of tag names.
# @return true on success, undef on error
sub add_recipe_tags {
    my $self     = shift;
    my $recipeid = shift;
    my $tags     = shift;

    # exit immediately if the tags list is empty; this is not an error, as the
    # recipe /can/ be untagged.
    return 1 if(!$tags);

    # If tags isn't a reference, assume it's a scalar string
    if(!ref($tags)) {
        return 1 unless(length($tags));

        # Split the tag after removing any extraneous whitespace between tags
        $tags =~ s/\s*,\s*/,/g;
        my @values = split(/,/, $tags);

        $tags = \@values;

    # If $tags is a reference, it has to be an array!
    } elsif(ref($tags) ne "ARRAY") {
        return $self -> self_error("Unsupported reference passed to add_recipe_tags(). Giving up.");
    }

    # Now we prepare the tag insert query for action
    my $addh = $self -> {"dbh"} -> prepare("INSERT INTO ".$self -> {"settings"} -> {"database"} -> {"recipetags"}."
                                            (`recipe_id`, `tag_id`)
                                            VALUES(?, ?)");

    # Go through each tag, adding it
    foreach my $tag (@{$tags}) {
        # Try to get the tag id
        my $tagid = $self -> {"system"} -> {"tags"} -> get_id($tag)
            or return $self -> self_error("Unable to obtain ID for tag '$tag'");

        $addh -> execute($recipeid, $tagid)
            or return $self -> self_error("Tag association failed: ".$self -> {"dbh"} -> errstr);

        $self -> {"system"} -> {"tags"} -> increase_refcount($tagid)
            or return $self -> self_error("Tag refcount change failed");
    }

    return 1;
}


# ==============================================================================
#  Metadata related

## @method $ get_recipe_metadata($recipeid)
# Given a recipe ID, fetch the ID of the metadata context associated with the
# recipe.
#
# @param recipeid The ID of the recipe to fetch the context ID for
# @return A metadata context ID on success, undef on error.
sub get_recipe_metadata {
    my $self     = shift;
    my $recipeid = shift;

    $self -> clear_error();

    my $metah = $self -> {"dbh"} -> prepare("SELECT `metadata_id`
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                             WHERE `id` = ?");
    $metah -> execute($recipeid)
        or return $self -> self_error("Unable to execute recipe metadata lookup query: ".$self -> {"dbh"} -> errstr);

    my $meta = $metah -> fetchrow_arrayref()
        or return $self -> self_error("Request for non-existent recipe '$recipeid', giving up");

    return $meta -> [0];
}

## @method private $ _create_recipe_metadata($previd)
# Create a metadata context for a new recipe. This will create the new context
# as a child of the metadata context for the specific previous recipe, if one
# is provided, to allow cascading permissions.
#
# @param previd Optional ID of the previous recipe. This should be set when
#               editing a recipe; for new recipes, leave this as undef or 0.
# @return The ID of a new metadata context to attach the recipe to on success,
#         undef on error.
sub _create_recipe_metadata {
    my $self   = shift;
    my $previd = shift;

    if($previd) {
        my $parentid = $self -> get_recipe_metadata($previd)
            or return undef;

        return $self -> {"metadata"} -> create($parentid);
    }

    return $self -> {"metadata"} -> create($self -> {"settings"} -> {"config"} -> {"Recipe:base_metadata"} // 1);
}

1;
