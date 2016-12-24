## @file
# This file contains the implementation of the Entity model class.
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

## @class Entity
# This is a model class for entities in the system, providing common
# features for all of the entities. Entities are any simple named
# object in the system, typically things like ingredients, prep
# memthods, recipe types and states.
#
# Tables for entities must have a minimum of the following fields:
#
# name        | type, max size | contents/notes
# ------------|----------------|--------------------------------------------------------------
# id          | unsigned int   | The ID of the entity; ensure auto incremement
# name        | varchar        | Entity name, size depends on entity, utf8_unicode_ci charset recommended
# refcount    | unsigned int   | How many uses of this are there?
package ORB::System::Entity;

# Current uses of this module:
#
# - ingredients
# - preparation methods
# - states
# - tags
# - types
# - units

use strict;
use parent qw(Webperl::SystemModule);
use v5.14;

use Webperl::Utils qw(hash_or_hashref);


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Create a new Entity object to manage entity creation and management.
# The minimum values you need to provide are:
#
# - `dbh`          - The database handle to use for queries.
# - `settings`     - The system settings object
# - `logger`       - The system logger object.
# - `entity_table` - The name of the table the entities are stored in.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Entity object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_);

    return SystemModule::set_error("No entity table specified when attempting to create object")
        if(!$self -> {"entity_table"});

    return $self
}


# ============================================================================
#  Entity creation and deletion

## @method $ create($name)
# Attempt to create a new named entity in the entity table. Generally you
# should not call this directly, as it will create a new entity in the table
# even if an entity already exists with the same name: you will generally
# want to call get_id() instead, as that will determine whether that the
# entity already exists before calling this if it does not.
#
# @param name The name of the entity to add.
# @return The new entity ID on success, undef on error.
sub create {
    my $self  = shift;
    my $name  = shift;

    $self -> clear_error();

    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {$self -> {"entity_table"}}."`
                                            (`name`)
                                            VALUES(?)");
    my $rows = $newh -> execute($name);
    return $self -> self_error("Unable to perform ".$self -> {"entity_table"}." insert: ". $self -> {"dbh"} -> errstr) if(!$rows);
    return $self -> self_error($self -> {"entity_table"}." insert failed, no rows inserted") if($rows eq "0E0");

    # FIXME: This ties to MySQL, but is more reliable that last_insert_id in general.
    #        Try to find a decent solution for this mess...
    # NOTE: the DBD::mysql documentation doesn't actually provide any useful information
    #       about what this will contain if the insert fails. In fact, DBD::mysql calls
    #       libmysql's mysql_insert_id(), which returns 0 on error (last insert failed).
    #       There, why couldn't they bloody /say/ that?!
    my $id = $self -> {"dbh"} -> {"mysql_insertid"};
    return $self -> self_error("Unable to obtain id for entity '$name'") if(!$id);

    return $id;
}


## @method $ destroy(%args)
# Attempt to remove the specified entity, and any assignments of it, from the system.
# Supported arguments are:
#
# - `id`:        The ID of the entity to remove. If not specified, a name must be given.
# - `name`:      The name of the entity to remove. If ID is specified, this is ignored.
# - `relations`: A hash containing `name` and `field` fields specifying the table
#                to remove any relations from. This may be specified as a
#                reference to an array of hashes.
#
# @param args A hash, or reference to a hash, or argument.
# @return true on success, undef on error
sub destroy {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    return $self -> self_error("No id or name specified in call to destroy")
        unless($args -> {"id"} || $args -> {"name"});

    # Convert name to ID if needed
    if(!$args -> {"id"}) {
        my $id = $self -> find_ids($args -> {"name"})
            or return undef;

        return $self -> self_error("No match for specified entity name '".$args -> {"name"}."'")
            unless(scalar(@{$id}));

        return $self -> self_error("Multiple matches for specified entity name '".$args -> {"name"}."'. Destroy unsafe, aborting")
            if(scalar(@{$id}) > 1);

        $args -> {"id"} = $id -> [0] -> {"id"};
    }

    # fall over if the relations argument is specified, but it's not a hash or arrayref
    return $self -> self_error("destroy invoked with invalid relations data")
        if($args -> {"relations"} &&
           ref($args -> {"relations"} ne "HASH" && ref($args -> {"relations"}) ne "ARRAY"));

    # Force arrayref of hashes for simplicity
    $args -> {"relations"} = [ $args -> {"relations"} ]
        if($args -> {"relations"} && ref($args -> {"relations"} eq "HASH"));

    # Process and remove each relation... or possibly none if there are none.
    foreach my $relation (@{$args -> {"relations"}}) {
        return $self -> self_error("Relation hash data invalid")
            unless($relation -> {"table"} && $relation -> {"field"});

        $self -> remove_relation($args -> {"id"}, $relation -> {"table"}, $relation -> {"field"})
            or return undef;
    }

    # Check that the entity is safe to delete...
    my $refcount = $self -> _fetch_refcount($args -> {"id"});

    return $self -> self_error("Attempt to delete non-existent entity ".$args -> {"id"}." from ".$self -> {"entity_table"})
        unless(defined($refcount));

    return $self -> self_error("Attempt to delete entity ".$args -> {"id"}." in ".$self -> {"entity_table"}." while still in use ($refcount references)")
        if($refcount);

    # And now delete the entity itself
    my $nukeh = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {$self -> {"entity_table"}}."`
                                             WHERE `id` = ?");
    $nukeh -> execute($args -> {"id"})
        or return $self -> self_error("Unable to perform entity ".$args -> {"id"}." removal from ".$self -> {"entity_table"}.": ". $self -> {"dbh"} -> errstr);

    return 1;
}


# ============================================================================
#  Lookup

## @method $ get_id($name)
# Obtain the ID associated with the specified entity. If the entity
# does not yet exist in the entity's table, this will create it and
# return the id the new entity was allocated.
#
# @param name The name of the entity to obtain the ID for
# @return The ID of the entity on success, undef on error.
sub get_id {
    my $self = shift;
    my $name = shift;

    my $id = $self -> find_ids($name)
        or return undef;

    # Single result, return that ID.
    return $id -> [0] -> {"id"}
        if(scalar(@{$id} == 1));

    # Multiple results are potentially dangerous. Log it as an error, but return the first hit anyway
    if(scalar(@{$id}) > 1) {
        $self -> self_error("Multiple matches for specified entity name '$name'");
        return $id -> [0]
    }

    # Get here, and $id is zero - no entity exists with the specified name, so
    # a new entity is needed.
    return $self -> create($name);
}


## @method $ find_ids($names)
# Given a name, or list of names, obtain the IDs that correspond to those names in the
# entity table. Note that, unlike get_id(), this will not create entities if no matching
# name is found.
#
# @param names The name of the entity to find, or a reference to an array of names.
# @return A reference to an array of hashes containing the names and ID(s) of the
#         entities with the specified names on success, an empty arrayref if no
#         matches exist, undef on error occurred.
sub find_ids {
    my $self  = shift;
    my $names = shift;

    $self -> clear_error();

    # No names, nothing to do.
    return [] unless($names);

    # Make sure that the names is an arrayref for easier processing.
    $names = [ $names ]
        unless(ref($names) eq "ARRAY");

    # Check and fixup the specified names.
    foreach my $name (@{$names}) {
        # All elements must be non-null/empty
        return $self -> self_error("Invalid undef/empty argument passed to find_ids()")
            unless($name);

        # Replace any wildcard markers
        $name =~ s/\*/%/g;
    }

    # Build and execute a query that matches the specified name(s)
    my $wherefrag = join(" OR ", (("`name` LIKE ?") x scalar(@{$names})));
    my $entityh = $self -> {"dbh"} -> prepare("SELECT `id`,`name`
                                               FROM `".$self -> {"settings"} -> {"database"} -> {$self -> {"entity_table"}}."`
                                               WHERE $wherefrag
                                               ORDER BY `name`,`id`");
    $entityh -> execute(@{$names})
        or return $self -> self_error("Unable to perform entity lookup: ".$self -> {"dbh"} -> errstr);

    # And return the list of matches
    return $entityh -> fwetchall_arrayref({});
}


# ============================================================================
#  Relation handling

## @method $ remove_relation($id, $table, $field, $retain_unused)
# Remove any relations to the specified entity from the table provided.
# This will decrease the refcount for the entity.
#
# @param id    The Id of the entity to remove the relation for.
# @param table The name of the table containing the relation to remove.
# @param field The field containing the entity ID in the relation table.
# @param retain_unused If true, do not delete the entity even if its refcount will
#                      be zero after calling this. Defaults to true.
# @return true on success, false on error.
sub remove_relation {
    my $self  = shift;
    my $id    = shift;
    my $table = shift;
    my $field = shift;
    my $retain_unused = shift // 1;

    $self -> clear_error();

    my $removeh = $self -> {"dbh"} -> prepare("DELETE FROM `$table`
                                               WHERE `$field` = ?");
    my $rows = $removeh -> execute($id);
    return $self -> self_error("Unable to remove entity relations to $id from $table") if(!$rows);
    return 1 if($rows eq "0E0"); # Zero row removal is possible and not an error

    my $result = $self -> _update_refcount($id, subtract => $rows);
    return undef if(!defined($result));

    # Nuke the entity if there's no reason to keep it around.
    return $self -> destroy($id)
        unless($retain_unused || $result);

    return defined($result);
}


# ============================================================================
#  Reference counting

## @method $ increase_refcount($id)
# Increase the refcount for the entity with the specified id.
#
# @param id The ID of the entity to increase the refcount for.
# @return true on success (actually, the reference count), false on error.
sub increase_refcount {
    my $self = shift;
    my $id   = shift;

    return $self -> _update_refcount($id, add => 1);
}


## @method $ decrease_refcount($id, $retain_unused)
# Reduce the refcount for the entity with the specified id. If the refcount
# becomes zero, and $retain_unused is not true, the entity is removed from
# the system.
#
# @param id            The ID of the entity to decrease the refcount for.
# @param retain_unused If true, do not delete the entity even if its refcount will
#                      be zero after calling this. Defaults to true.
# @return true on success, false on error.
sub decrease_refcount {
    my $self          = shift;
    my $id            = shift;
    my $retain_unused = shift // 1;

    # Change the refcount, bomb if the change failed.
    my $result = $self -> _update_refcount($id, subtract => 1);
    return undef if(!defined($result));

    # Nuke the entity if there's no reason to keep it around.
    return $self -> destroy($id)
        unless($retain_unused || $result);

    return defined($result);
}


# ============================================================================
#  Reference handling - generally intended only for subclasses to use

## @method protected $ _fetch_refcount($id)
# Obtain the reference count for the specified entity. This will attempt to
# fetch the reference count for the entity, if it fails - because the entity
# does not exist, or the database has shat itself - it will return undef.
#
# @param id The entity to fetch the reference count for.
# @return The number of references to the entity (which may be zero), or undef
#         on error.
sub _fetch_refcount {
    my $self = shift;
    my $id   = shift;

    $self -> clear_error();

    # Simple lookup, nothing spectacular to see here...
    my $refh = $self -> {"dbh"} -> prepare("SELECT `refcount`
                                            FROM `".$self -> {"settings"} -> {"database"} -> {$self -> {"entity_table"}}."`
                                            WHERE `id` = ?");
    $refh -> execute($id)
        or return $self -> self_error("Unable to perform entity refcount lookup: ". $self -> {"dbh"} -> errstr);

    my $refcount = $refh -> fetchrow_arrayref();
    return $refcount ? $refcount -> [0] : $self -> self_error("Unable to locate entity ".$self -> {"entity_table"}."[$id]: does not exist");
}


## @method protected $ _update_refcount($id, %operation)
# Update the refcount for the specified entity. This will increment, decrement,
# or set the value stored in the specified entity's reference counter. This is the
# actual implementation underlying increase_refcount() and decrease_refcount().
#
# @param id        The ID of the entity to update the refcount for.
# @param operation A hash containing one of 'add', 'subtract', or 'set' with
#                  values that indicate how much to change the refcount by.
# @return The new value of the reference count on success (which may be zero), undef on error.
sub _update_refcount {
    my $self      = shift;
    my $id        = shift;
    my %operation = @_;

    $self -> clear_error();

    my $refcount = $self -> _fetch_refcount($id);
    return undef if(!defined($refcount));

    # Calculate the new refcount
    if(defined($operation{"add"})) {
        $refcount += $operation{"add"};
    } elsif(defined($operation{"subtract"})) {
        $refcount -= $operation{"subtract"};
    } elsif(defined($operation{"set"})) {
        $refcount = $operation{"set"};
    } else {
        return $self -> self_error("No valid operation specified in call to _update_refcount() for ".$self -> {"entity_table"}."[$id]");
    }

    # Is the new refcount sane?
    return $self -> self_error("New refount of $refcount for entity ".$self -> {"entity_table"}."[$id]: is invalid")
        if($refcount < 0 || ($self -> {"max_refcount"} && $refcount > $self -> {"max_refcount"}));

    # Update is safe, do the operation.
    my $atth = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {$self -> {"entity_table"}}."`
                                            SET `refcount` = ?
                                            WHERE `id` = ?");
    my $result = $atth -> execute($refcount, $id);
    return $self -> self_error("Unable to update entity refcount: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Entity refcount update failed: no rows updated. This should not happen!") if($result eq "0E0");

    return $refcount;
}

1;
