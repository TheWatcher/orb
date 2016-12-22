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
# +-------------+--------------------------------+------+-----+----------------+
# | Field       | Type                           | Null | Key | Extra          |
# +-------------+--------------------------------+------+-----+----------------+
# | id          | int(10) unsigned               | NO   | PRI | auto_increment |
# | prev_id     | int(11)                        | YES  |     |                |
# | metadata_id | int(11)                        | NO   |     |                |
# | name        | varchar(80)                    | NO   | UNI |                |
# | method      | text                           | NO   |     |                |
# | notes       | text                           | YES  |     |                |
# | source      | varchar(255)                   | YES  |     |                |
# | yield       | varchar(80)                    | NO   |     |                |
# | timereq     | varchar(255)                   | NO   |     |                |
# | timemins    | int(10) unsigned               | NO   | MUL |                |
# | temptype    | enum('C','F','Gas mark','N/A') | NO   |     |                |
# | temp        | smallint(5) unsigned           | YES  |     |                |
# | type_id     | int(10) unsigned               | NO   | MUL |                |
# | status_id   | int(10) unsigned               | NO   | MUL |                |
# | creator_id  | int(10) unsigned               | NO   |     |                |
# | created     | int(10) unsigned               | NO   | MUL |                |
# | viewed      | int(10) unsigned               | NO   |     |                |
# +-------------+--------------------------------+------+-----+----------------+

# +-----------+------------------+------+-----+----------------+
# | Field     | Type             | Null | Key | Extra          |
# +-----------+------------------+------+-----+----------------+
# | id        | int(10) unsigned | NO   | PRI | auto_increment |
# | recipe_id | int(10) unsigned | NO   | MUL |                |
# | unit_id   | int(10) unsigned | YES  |     |                |
# | prep_id   | int(10) unsigned | YES  |     |                |
# | ingred_id | int(10) unsigned | YES  |     |                |
# | quantity  | varchar(8)       | YES  |     |                |
# | notes     | varchar(255)     | YES  |     |                |
# | separator | varchar(255)     | YES  |     |                |
# +-----------+------------------+------+-----+----------------+
#
#

package ORB::System::Recipe;

use strict;
use parent qw(Webperl::SystemModule);
use v5.14;

use experimental qw(smartmatch);
use Webperl::Utils qw(hash_or_hashref array_or_arrayref);


# ============================================================================
#  Constructor and cleanup

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


## @method void clear()
# Delete all references to entity management objects from the current recipe
# object. This helps teardown after page generation by making life easier for
# perl's destructor code.
#
sub clear {
    my $self = shift;

    delete $self -> {"entities"};
}


# ============================================================================
#  Recipe creation and status modification

## @method $ create(%args)
# Create a new recipe in the system. The args hash can contain the following,
# all fields are required unless indicated otherwise:
#
# -      `previd`: (optional) ID of the recipe this is an edit of. If specified,
#                  the old recipe has its state set to 'edited', and the
#                  metadata context of the new recipe is created as a child of
#                  the old recipe to ensure editing works as expected. Generally
#                  this will not be specified directly; if editing a recipe,
#                  call edit() to have renumbering handled for you.
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
#                  documentation for _add_ingredients() for the
#                  required hash values
# -        `tags`: The tags to set for the recipe, may be either a comma
#                  separated string of tags, or a reference to an array
#                  of tags. May be undef or an empty string.
#
# @param args A hash, or reference to a hash, of values to use when creating
#             the new recipe.
# @return The new recipe ID on success, undef on error.
sub create {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    # Get IDs for the type and status
    $args -> {"typeid"} = $self -> {"entities"} -> {"types"} -> get_id($args -> {"type"})
        or return $self -> self_error($self -> {"entities"} -> {"types"} -> errstr());

    $args -> {"statusid"} = $self -> {"entities"} -> {"states"} -> get_id($args -> {"status"})
        or return $self -> self_error($self -> {"entities"} -> {"states"} -> errstr());

    # We need a metadata context for the recipe
    my $metadataid = $self -> _create_recipe_metadata($args -> {"previd"});

    # Do the insert, and fetch the ID of the new row
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                            (`id`, `metadata_id`, `prev_id`, `name`, `source`, `timereq`, `timemins`, `yield`, `temp`, `temptype`, `method`, `notes`, `type_id`, `status_id`, `creator_id`, `created`)
                                            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, UNIX_TIMESTAMP())");
    my $result = $newh -> execute($args -> {"id"}, $metadataid, $args -> {"previd"}, $args -> {"name"}, $args -> {"source"}, $args -> {"timereq"}, $args -> {"timemins"}, $args -> {"yield"}, $args -> {"temp"}, $args -> {"temptype"}, $args -> {"method"}, $args -> {"notes"}, $args -> {"typeid"}, $args -> {"statusid"}, $args -> {"creatorid"});
    return $self -> self_error("Insert of recipe failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows added when inserting recipe.")
        if($result eq "0E0");

    my $newid = $self -> {"dbh"} -> {"mysql_insertid"};

    return $self -> self_error("Unable to obtain id for new recipe")
        if(!$newid);

    # Attach to the metadata context as it's in use now
    $self -> {"metadata"} -> attach($metadataid)
        or return $self -> self_error("Error in metadata system: ".$self -> {"metadata"} -> errstr());

    # Add the ingredients for the recipe
    $self -> _add_ingredients($newid, $args -> {"ingredients"})
        or return undef;

    # And the tags
    $self -> _add_tags($newid, $args -> {"tags"})
        or return undef;

    return $newid;
}


## @method $ edit(%args)
# Edit the specified recipe. This will retain edit history, so that previous
# versions of a recipe may be accessed at any time, and keep the live ID of
# the recipe the same (previous versions get moved to new IDs, then the
# updated recipe overwrites the data at the old ID).
#
# @param args This should be a reference to a hash containing the same
#             elements as the args hash for create(), except previd is
#             required here
# @return The recipe Id on success, undef on error.
sub edit {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    return $self -> self_error("edit called without previous recipe ID")
        unless($args -> {"previd"});

    # Move the old recipe to the end of the table, but keep a record
    # of its current ID
    $args -> {"id"}     = $args -> {"previd"};
    $args -> {"previd"} = $self -> _renumber_recipe($args -> {"previd"});

    # Create a new one at the old ID
    $self -> create($args)
        or return undef;

    # Set the status of the edited recipe
    $self -> set_state($args -> {"previd"},
                       $self -> {"settings"} -> {"config"} -> {"Recipe:status:edited"} // "edited")
        or return undef;

    return $args -> {"id"};
}


## @method $ set_status($recipeid, $status)
# Set the recipe status to the specified value. This will convert the provided
# status to a status ID and set that as the status if the recipe.
#
# @note The settings table may define a number of special state names, with
#       the setting names 'Recipe:status:edited' and 'Recipe:status:deleted'
#
# @param recipeid The ID of the recipe to set the status for.
# @param status   The status of the recipe. This should be a string, not an ID.
# @return true on success, undef on error.
sub set_status {
    my $self     = shift;
    my $recipeid = shift;
    my $status   = shift;

    $self -> clear_error();

    my $statusid = $self -> {"entities"} -> {"states"} -> get_id($status)
        or return $self -> self_error($self -> {"entities"} -> {"states"} -> errstr());

    my $stateh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                              SET `status_id` = ?
                                              WHERE `id` = ?");
    my $result = $stateh -> execute($statusid, $recipeid);
    return $self -> self_error("Status update of recipe failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows modified when updating recipe state.")
        if($result eq "0E0");

    return 1;
}


# ============================================================================
#  Recipe retrieval

## @method $ get_recipe($recipeid)
# Given a recipe ID, attempt to fetch the data for the recipe, including its
# ingredient and tags lists.
#
# @param recipeid The ID of the recipe to fetch the data for
# @return A reference to a hash contianing the recipe data on success, an
#         empty hash if the recipe can't be located, and undef on error.
sub get_recipe {
    my $self     = shift;
    my $recipeid = shift;

    $self -> clear_error();

    # Fetch the recipe itself, along with names of singular relations
    my $recipeh = $self -> {"dbh"} -> prepare("SELECT `r`.*, `s`.`name` AS `status`, `t`.`name` AS `type`, `u`.`user_id`, `u`,`username`, `u`,`realname`
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"recipes"}."` AS `r`,
                                                    `".$self -> {"settings"} -> {"database"} -> {"states"}."` AS `s`,
                                                    `".$self -> {"settings"} -> {"database"} -> {"types"}."` AS `t`
                                               WHERE `s`.`id` = `r`.`status_id`
                                               AND `t`.`id` = `r`.`type_id`
                                               AND `r`.`id` = ?");
    $recipeh -> execute($recipeid)
        or return $self -> self_error("Unable to perform recipe lookup: ".$self -> {"dbh"} -> errstr);

    my $recipe = $recipeh -> fetchrow_hashref()
        or return {}; # Empty hash on missing recipe

    # Should be everything specifically recipe related now...
    return $self -> load_recipe_relations($recipe)
}


## @method $ load_recipe_relations($recipe)
# Fetch the supporting information for the specified recipe. This will load
# additional information about the recipe (ingredients, tags, ...) into the
# recipe hash.
#
# @param recipe A reference to a hash containing the recipe data
# @return A reference to a hash containing the expanded recipe data.
sub load_recipe_relations {
    my $self   = shift;
    my $recipe = shift;

    $recipe -> {"ingredients"} = $self -> _get_ingredients($recipe -> {"id"})
        or return undef;

    $recipe -> {"tags"} = $self -> _get_tags($recipe -> {"id"})
        or return undef;

    return $recipe;
}


## @method $ find(%args)
# Attempt to locate recipes that match the criteria specified. Supported search
# criteria are given below. Criteria marked with * perform embedded string
# matching, and may further contain % or * to do additional matching, and
# all the criteria are optional.
#
# - `name`: search based on strings in the name field*
# - `method`: search based on strings in the method*
# - `notes`: search based on strings in the notes*
# - `type`: find recipes of the specified type.
# - `status`: find recipes with the specified status.
# - `time`: do a time-based search. This should be a time required in minutes.
#           How this operates depends on the value of `timemode`.
# - `timemode`: control how time searching works. This can either be '>=' or
#           '<=': in the former case the search will return recipes that take
#           `time` minutes or more, in the latter it will find recipes that
#           take `time` minutes or less. Defaults to '<='.
# - `ingredients`: A reference to an array of ingredient names. This allows
#           the caller to search for recipes that use the specified ingredients
#           subject to the logic imposed by `ingredmatch`. Automatic substring
#           matching *is not* performed for ingredients, but * or % in the
#           ingredient names may be used to do wildcard searches.
# - `ingredmatch`: Control how ingredient searching works. This can either be
#           "all" or "any" (default is "all"). If this is set to "all", only
#           recipes that use all the specified ingredients are returned, if
#           it is set to "any" then recipes that use any of the ingredients
#           will be returned.
# - `tags`: A reference to an array of tag names. This allows the caller to
#           search for recipes with one or more tags associated with them,
#           subject to the logic imposed by `tagmatch`. Automatic substring
#           matching *is not* performed for tags, but * or % in the
#           tag names may be used to do wildcard searches.
# - `tagmatch`: control how tag searching works. As with `ingredmatch`, this
#           may be "all" or "any", with corresponding behaviour.
# - `limit`: how many recipies may be returned by the find()
# - `offset`: offset from the start of the query results.
# - `searchmode`: This may be "all", in which only recipes that match all the
#           specified criteria are returned, or "any" in which case
#           recipes that match any of the criteria will be returned. This
#           defaults to "all". Note that this breaks slightly with ingredient
#           and tag searching: if the `ingredmatch` or `tagmatch` are set to
#           "all", only recipes that pass those checks will have any other
#           search criteria applied to them - recipes that do not match
#           will not be considered, even if they might match other criteria.
#
# @param args A hash, or reference to a hash, of criteria to use when searching.
# @return A reference to an array of recipe records.
sub find {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    # Convert ingredients and tags to IDs for easier query structure
    # This will return an empty array if there are no ingredients to search on
    my $ingreds = $self -> {"entities"} -> {"ingredients"} -> find_ids($args -> {"ingredients"})
        or return $self -> self_error("Ingredient lookup error: ".$self -> {"entities"} -> {"ingredients"} -> errstr());

    # Fix the array returned from find_ids so that we only have the id numbers
    $args -> {"ingredids"} = $self -> _hashlist_to_list($ingreds, "id");

    # Repeat the process for the recipe tags
    my $tags = $self -> {"entities"} -> {"tags"} -> find_ids($args -> {"tags"})
        or return $self -> self_error("Tag lookup error: ".$self -> {"entities"} -> {"tags"} -> errstr());
    $args -> {"tagids"} = $self -> _hashlist_to_list($tags, "id");

    # Fix up default matching modes
    $args -> {"ingredmatch"} = "all" unless($args -> {"ingredmatch"} eq "any");
    $args -> {"tagmatch"}    = "all" unless($args -> {"tagmatch"} eq "any");

    # Now start the process of building the query
    my (@params, $joins, @where) = ((), "", ());

    # Matching all ingredients or tags requires multiple inner joins
    $joins .= $self -> _join_fragment($args -> {"ingredids"}, $self -> {"entities"} -> {"ingredients"} -> {"entity_table"}, \@params)
        if(scalar(@{$args -> {"ingredids"}}) && $args -> {"ingredmatch"} eq "all");
    $joins .= $self -> _join_fragment($args -> {"tagids"}, $self -> {"entities"} -> {"tags"} -> {"entity_table"}, \@params)
        if(scalar(@{$args -> {"tagids"}}) && $args -> {"tagmatch"} eq "all");

    # Simple searches on recipe fields
    push(@where, $self -> _where_fragment("`r`.`name` LIKE ?", $args -> {"name"}, 1, \@params))
        if($args -> {"name"});

    push(@where, $self -> _where_fragment("`r`.`method` LIKE ?", $args -> {"method"}, 1, \@params))
        if($args -> {"method"});

    push(@where, $self -> _where_fragment("`r`.`notes` LIKE ?", $args -> {"notes"}, 1, \@params))
        if($args -> {"notes"});

    push(@where, $self -> _where_fragment("`st`.`name` LIKE ?", $args -> {"status"}, 0, \@params))
        if($args -> {"status"});

    push(@where, $self -> _where_fragment("`ty`.`name` LIKE ?", $args -> {"type"}, 0, \@params))
        if($args -> {"type"});

    # Handling time specification is a bit tricker.
    if($args -> {"time"} && $args -> {"time"} =~ /^\d+$/) {
        $args -> {"timemode"} = "<=" unless($args -> {"timemode"} eq ">=");
        push(@where, $self -> _where_fragment("`r`.`timereq` ".$args -> {"timemode"}." ?", $args -> {"time"}, 0, \@params));
    }

    # Handle 'OR' case for ingredients and tags
    if(scalar(@{$args -> {"ingredids"}}) && $args -> {"ingredmatch"} eq "any") {
        $joins .= " INNER JOIN `".$self -> {"settings"} -> {"database"} -> {"recipeing"}."` AS `ri` ON `r`.`id` = `ri`.`recipe_id` ";
        push(@where, $self -> _multi_where_fragment("`ri`.`ingred_id` IN ", $args -> {"ingredids"}, \@params));
    }

    if(scalar(@{$args -> {"tagids"}}) && $args -> {"tagmatch"} eq "any") {
        $joins .= " INNER JOIN `".$self -> {"settings"} -> {"database"} -> {"recipetags"}."` AS `rt` ON `r`.`id` = `rt`.`recipe_id` ";
        push(@where, $self -> _multi_where_fragment("`rt`.`tag_id` IN ", $args -> {"tagids"}, \@params));
    }

    # Squish all the where conditions into a string
    my $wherecond = join(($args -> {"searchmode"} eq "any" ? "\nOR " : "\nAND "), @where);

    # Construct the limit term when limit (and optionally offset) are
    # specified by the caller
    my $limit = "";
    if($args -> {"limit"} && $args -> {"limit"} =~ /^\d+$/) {
        $limit = "LIMIT ";
        $limit .= $args -> {"offset"}.", "
            if($args -> {"offset"} && $args -> {"offset"} =~ /^\d+$/);

        $limit .= $args -> {"limit"};
    }

    my $order;
    given($args -> {"order"}) {
        when("added")  { $order = "`r`.`created` DESC, `r`.`name` ASC"; }
        when("viewed") { $order = "`r`.`viewed` DESC, `r`.`name` ASC"; }

        default { $order = "`r`.`name` ASC, `r`.`created` DESC"; }
    }

    # Build and run the search query
    my $query = "SELECT DISTINCT `r`.*, `s`.name` AS `status`, `t`.`name` AS `type`, `c`.`username`, `c`.`email`, `c`.`realname`
                 FROM `".$self -> {"settings"} -> {"database"} -> {"recipes"}."` AS `r`
                 INNER JOIN `".$self -> {"settings"} -> {"database"} -> {"states"}."` AS `s` ON `s`.`id` = `r`.`status_id`
                 INNER JOIN `".$self -> {"settings"} -> {"database"} -> {"types"}."` AS `t` ON `t`.`id` = `r`.`type_id`
                 INNER JOIN `".$self -> {"settings"} -> {"database"} -> {"users"}."` AS `u` ON `u`.`user_id` = `r`.`creator_id`
                 $joins
                 WHERE $wherecond
                 ORDER BY $order
                 $limit";
    my $search = $self -> {"dbh"} -> prepare($query);
    $search -> execute(@params)
        or return $self -> self_error("Unable ot perform recipe search: ".$self -> {"dbh"} -> errstr);

    return $search -> fetchall_arrayref({});
}


# ==============================================================================
#  Private methods

## @method private $ _add_ingredients($recipeid, $ingredients)
# Add the specified ingredients to the recipe list for the specified recipe.
# This goes through the array of ingredients and adds each entry to the
# ingredient list for the specified recipe. The ingredients are specified
# as an array of hashrefs, each hash should contain the following keys:
#
# - `separator`: if true, the ingredient is a separator, `name` is set
#                as the separator line title, and all the other fields
#                are ignored.
# -      `name`: the ingredient name (or separator title if `separator` is true.
# -     `quant`: a string describing the quantity. Note that this may be
#                anything from a simple numeric value to "some".
# -     `units`: The units to use for the quantity. May be undef.
# -      `prep`: A string describing the preparation method.
# -     `notes`: Optional notes for the ingredient.
#
# @param recipeid    The id of the recipe to add the ingredients to.
# @param ingredients A reference to an array of hashes containing ingredient
#                    specifications.
# @return true on success, undef on error
sub _add_ingredients {
    my $self        = shift;
    my $recipeid    = shift;
    my $ingredients = shift;

    # Prepare the add query to make work easier later
    my $addh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"recipeing"}."`
                                            (`recipe_id`, `position`, `unit_id`, `prep_id`, `ingred_id`, `quantity`, `notes`, `separator`)
                                            VALUES(?, ?, ?, ?, ?, ?, ?, ?)");

    # Now go through each of the ingredients
    my $position = 0;
    foreach my $ingred (@{$ingredients}) {

        # Handle serparators... separately
        if($ingred -> {"separator"}) {
            $addh -> execute($recipeid, $position, undef, undef, undef, undef, undef, $ingred -> {"name"})
                or return $self -> self_error("Error adding separator '".$ingred -> {"name"}."': ".$self -> {"dbh"} -> errstr());

        # Otherwise, it's a real ingredient, so we need to do the more complex work
        } else {
            # obtain the IDs of entities referenced by this ingredient relation
            my $ingid = $self -> {"entities"} -> {"ingredients"} -> get_id($ingred -> {"name"})
                or return $self -> self_error("Unable to get ingreditent ID for '".$ingred -> {"name"}."': ".$self -> {"entities"} -> {"ingredients"} -> errstr());

            my $unitid = $self -> {"entities"} -> {"units"} -> get_id($ingred -> {"units"})
                or return $self -> self_error("Unable to get unit ID for '".$ingred -> {"units"}."': ".$self -> {"entities"} -> {"units"} -> errstr());

            my $prepid = $self -> {"entities"} -> {"prep"} -> get_id($ingred -> {"prep"})
                or return $self -> self_error("Unable to get preparation method ID for '".$ingred -> {"prep"}."': ".$self -> {"entities"} -> {"prep"} -> errstr());

            # If we have an ID we can add the ingredient.
            $addh -> execute($recipeid, $position, $unitid, $prepid, $ingid, $ingred -> {"quant"}, $ingred -> {"notes"}, undef)
                or return $self -> self_error("Unable to add ingredient '".$ingred -> {"name"}."' to recipe '$recipeid': ".$self -> {"dbh"} -> errstr());

            # And increase the entity refcounts
            $self -> {"entities"} -> {"ingredients"} -> increase_refcount($ingid);
            $self -> {"entities"} -> {"units"}       -> increase_refcount($unitid);
            $self -> {"entities"} -> {"prep"}        -> increase_refcount($prepid);
        }

        ++$position;
    }

    # Get here and all worked out okay
    return 1;
}


## @method private $ _add_tags($recipeid, $tags)
# Add the specified tags to a recipe.
#
# @param recipeid  The id of the recipe to add the tags to.
# @param tags      A string containing a comma-delimited list of tags, or a
#                  reference to an array of tag names.
# @return true on success, undef on error
sub _add_tags {
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
        return $self -> self_error("Unsupported reference passed to _add_tags(). Giving up.");
    }

    # Now we prepare the tag insert query for action
    my $addh = $self -> {"dbh"} -> prepare("INSERT INTO ".$self -> {"settings"} -> {"database"} -> {"recipetags"}."
                                            (`recipe_id`, `tag_id`)
                                            VALUES(?, ?)");

    # Go through each tag, adding it
    foreach my $tag (@{$tags}) {
        # Try to get the tag id
        my $tagid = $self -> {"entities"} -> {"tags"} -> get_id($tag)
            or return $self -> self_error("Unable to obtain ID for tag '$tag'");

        $addh -> execute($recipeid, $tagid)
            or return $self -> self_error("Tag association failed: ".$self -> {"dbh"} -> errstr);

        $self -> {"entities"} -> {"tags"} -> increase_refcount($tagid)
            or return $self -> self_error("Tag refcount change failed");
    }

    return 1;
}


## @method private $ _get_ingredients($recipeid)
# Fetch the ingredients for the specified recipe, along with any separators
# in the ingredient list
#
# @param recipeid The ID of the recipe to fetch the ingredients for.
# @return An arrayref of ingredient hashes on success, undef on error.
sub _get_ingredients {
    my $self     = shift;
    my $recipeid = shift;

    $self -> clear_error();

    my $ingh = $self -> {"dbh"} -> prepare("SELECT `ri`.*, `i`.`name`
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"recipeing"}."` AS `ri`
                                                 `".$self -> {"settings"} -> {"database"} -> {"ingredients"}."` AS `i`
                                            WHERE `i`.`id` = `ri`.`ingred_id`
                                            AND `ri`.`recipe_id` = ?
                                            ORDER BY `ri`.`position`");
    $ingh -> execute($recipeid)
        or return $self -> self_error("Ingredient lookup for '$recipeid' failed: ".$self -> {"dbh"} -> errstr());

    return $ingh -> fetchall_arrayref({});
}


## @method private $ _get_tags($recipeid)
# Fetch the tags for the specified recipe.
#
# @param recipeid The ID of the recipe to fetch the tags for.
# @return A reference to an array of tag names on success, undef on error.
sub _get_tags {
    my $self     = shift;
    my $recipeid = shift;

    $self -> clear_error();

    my $tagh = $self -> {"dbh"} -> prepare("SELECT `t`.`name`
                                            FROM `".$self -> {"settings"} -> {"database"} -> {"recipetags"}."` AS `rt`
                                                 `".$self -> {"settings"} -> {"database"} -> {"tags"}."` AS `t`
                                            WHERE `t`.`id` = `rt`.`ingred_id`
                                            AND `rt`.`recipe_id` = ?
                                            ORDER BY `t`.`name`");
    $tagh -> execute($recipeid)
        or return $self -> self_error("Tag lookup for '$recipeid' failed: ".$self -> {"dbh"} -> errstr());

    # No easy way to fetch a flat list of tags, so do it the mechanistic way...
    my @tags = ();
    while(my $tag = $tagh -> fetchrow_arrayref()) {
        push(@tags, $tag -> [0]);
    }

    return \@tags;
}


## @method private $ _renumber_recipe($sourceid)
# Given a recipe ID, move the recipe to a new ID at the end of the recipe
# table. This will move the recipe and all relations involving it, to
# a new ID at the end of the table, leaving the source ID available for
# use by a new recipe. Note that, as the ID field of the recipe table is
# an autoincrement, reusing the ID will require explicit specification
# of the ID in the insert.
#
# @param sourceid The ID of the recipe to move.
# @return The new ID of the recipe on success, undef on error.
sub _renumber_recipe {
    my $self     = shift;
    my $sourceid = shift;

    $self -> clear_error();

    # Duplicate the source recipe at the end of the table
    my $moveh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                            (`metadata_id`, `prev_id`, `name`, `method`, `notes`, `source`, `yield`, `timereq`, `timemins`, `temptype`, `temp`, `type_id`, `status_id`, `creator_id`, `created`, `viewed`)
                                                SELECT `metadata_id`, `prev_id`, `name`, `method`, `notes`, `source`, `yield`, `timereq`, `timemins`, `temptype`, `temp`, `type_id`, `status_id`, `creator_id`, `created`, `viewed`
                                                FROM `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                                WHERE `id` = ?");
    my $rows = $moveh -> execute($sourceid);
    return $self -> self_error("Unable to perform recipe move: ". $self -> {"dbh"} -> errstr) if(!$rows);
    return $self -> self_error("Recipe move failed, no rows inserted") if($rows eq "0E0");

    # Get the new ID
    my $newid = $self -> {"dbh"} -> {"mysql_insertid"}
        or return $self -> self_error("Unable to obtain id for new recipe");

    $self -> _fix_recipe_relations($sourceid, $destid)
        or return undef;

    # Nuke the old recipe
    my $remh = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"recipes"}."`
                                            WHERE `id` = ?");
    $rows = $remh -> execute($sourceid);
    return $self -> self_error("Unable to perform recipe move cleanup: ". $self -> {"dbh"} -> errstr) if(!$rows);
    return $self -> self_error("Recipe move cleanup failed, no rows inserted") if($rows eq "0E0");

    # Done, hand back the new ID number
    return $newid;
}


## @method private $ _fix_recipe_relations($sourceid, $destid)
# Correct all relations to the source recipe so that they refer to the
# destination. This is used as part of the renumbering process to
# fix up any relations that use the old recipe Id to use the new one.
#
# @param sourceid The ID of the old recipe.
# @param destid   The ID of the new recipe.
# @return true on success, undef on error.
sub _fix_recipe_relations {
    my $self     = shift;
    my $sourceid = shift;
    my $destid   = shift;

    $self -> clear_error();

    # Move ingredient relation IDs
    $moveh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"recipeing"}."`
                                          SET `recipe_id` = ?
                                          WHERE `recipe_id` = ?");
    $moveh -> execute($destid, $sourceid)
        or return $self -> self_error("Ingredient relation fixup failed: ".$self -> {"dbh"} -> errstr());

    # And fix up the tag relations too
    $moveh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"recipetags"}."`
                                          SET `recipe_id` = ?
                                          WHERE `recipe_id` = ?");
    $moveh -> execute($destid, $sourceid)
        or return $self -> self_error("Ingredient relation fixup failed: ".$self -> {"dbh"} -> errstr());

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


# ==============================================================================
#  Miscellaneous horribleness

## @method private $ _hashlist_to_list($hashlist, $field)
# Given a reference to an array of hashrefs, generate an array containing the
# values stored in specific fields in each hashref. For example, given an array
# that looks like
#
# [
#   { "id" => 10, "name" => "foo" },
#   { "id" => 11, "name" => "bar" },
#   { "id" => 12, "name" => "foobar" },
#   { "id" => 13, "name" => "barfoo" },
# ]
#
# if $field is set to "name", this will return the array
#
# [ 'foo', 'bar', 'foobar', 'barfoo' ]
#
# @param hashlist A reference to an array of hashrefs.
# @param field    The name of the field in the hash that contains the values
#                 to return.
# @return A reference to an array of values pulled out of the hashes.
sub _hashlist_to_list {
    my $self     = shift;
    my $hashlist = shift;
    my $field    = shift;

    my @res = map { $_ -> {$field} } @{$hashlist};

    return \@res;
}


## @method private $ _join_fragment($idlist, $table, $params)
# Generate an inner join fragment to append to the table list of a search
# query. This is used to restrict the results to recipes that use certain
# incredients or have specific tags associated with them.
#
# @param idlist A reference to an array of IDs to match with inner joins
# @param table  The relation table to join against
# @param params A reference to an array of parameters that will be passed
#               to execute() and replace value markers in the query
# @return A string containing the inner joins
sub _join_fragment {
    my $self   = shift;
    my $idlist = shift;
    my $table  = shift;
    my $params = shift;
    my $result = "";

    foreach my $id (@{$idlist}) {
        $result .= " INNER JOIN `$table` AS `ij$id` ON `r`.`id` = `ij$id`.`recipe_id` AND `ij$id`.`ingred_id` = ?";
        push(@{$params}, $id);
    }

    return $result;
}


## @method pricate $ _where_fragment($frag, $value, $wild, $params)
# Prepare values for inclusion in the WHERE section of the query
sub _where_fragment {
    my $self   = shift;
    my $frag   = shift;
    my $value  = shift;
    my $wild   = shift;
    my $params = shift;

    # Add missing % if wildcards are enabled
    if($wild) {
        $value = "%".$value unless($value =~ /^\%/);
        $value = $value."%" unless($value =~ /\%$/);
        $value =~ s/\*/%/g; # convert UI wildcard character to mysql
    }

    # And store the value in the execute parameters
    push(@{$params}, $value);

    return $frag;
}
1;
