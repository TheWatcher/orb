## @file
# This file contains the implementation of the Menu model.
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

package ORB::System::Menu;

use strict;
use parent qw(Webperl::SystemModule);
use v5.14;

use experimental qw(smartmatch);
use Webperl::Utils qw(hash_or_hashref array_or_arrayref);


# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Create a new Menu object to manage entity creation and management.
# The minimum values you need to provide are:
#
# - `dbh`          - The database handle to use for queries.
# - `settings`     - The system settings object
# - `logger`       - The system logger object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Menu object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(menu_root_context => 1,
                                        @_);

    return $self;
}


# ============================================================================
#  Menu creation and deletion

## @method $ create($name, $creatorid)
# Create a new menu. This creates a menu, and sets it as the active menu for
# the creator.
#
# @param name      The name of the menu - this does not need to be unique, but
#                  might be a good idea to be...
# @param creatorid The ID of the creator of the menu.
# @return The ID of the new menu.
sub create {
    my $self      = shift;
    my $name      = shift;
    my $creatorid = shift;

    $self -> clear_error();

    # even menus need a context...
    my $mdid = $self -> {"metadata"} -> create($self -> {"menu_root_context"});

    # Build the menu
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"menus"}."`
                                            (`metadata_id`, `name`, `creator_id`, `created`, `updated`)
                                            VALUES(?, ?, ?, UNIX_TIMESTAMP(), UNIX_TIMESTAMP())");
    my $result = $newh -> execute($mdid, $name, $creatorid);
    return $self -> self_error("Insert of menu failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows added when inserting menu.")
        if($result eq "0E0");

    my $newid = $self -> {"dbh"} -> {"mysql_insertid"};
    return $self -> self_error("Unable to obtain id for new menu")
        if(!$newid);

    # Attach to the metadata context as it's in use now
    $self -> {"metadata"} -> attach($mdid)
        or return $self -> self_error("Error in metadata system: ".$self -> {"metadata"} -> errstr());

    # Add the user as a menu editor
    my $roleid = $self -> {"system"} -> {"roles"} -> role_get_roleid("chef.editor");
    $self -> {"system"} -> {"roles"} -> user_assign_role($args -> {"metadataid"},
                                                         $args -> {"creatorid"},
                                                         $roleid)
        or return $self -> self_error($self -> {"system"} -> {"roles"} -> {"errstr"});

    # Set it as active so the caller doesn't need to care
    $self -> set_active_menu($creatorid, $newid)
        or return undef;

    return $newid;
}


## @method $ delete($menuid)
# Delete the specified menu. This will mark the menu as deleted (it does not
# actually delete the menu - it sets its `deleted` field to the current time)
# and remove any active menu selections for the menu.
#
# @param menuid The ID of the menu to delete.
# @return true on success, undef on error.
sub delete {
    my $self   = shift;
    my $menuid = shift;

    $self -> clear_error();

    # Mark as deleted
    my $nukeh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"menus"}."`
                                             SET `deleted` = UNIX_TIMESTAMP()
                                             WHERE `id` = ?");
    my $result = $newh -> execute($menuid);
    return $self -> self_error("Delete of menu failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows changed when deleting menu.")
        if($result eq "0E0");

    # Remove active references to the menu
    my $clearh = $self -> {"dbh"} -> prepare("UPDATE `".$self -> {"settings"} -> {"database"} -> {"active"}."`
                                              SET `menu_id` = undef
                                              WHERE `menu_id` = ?");
    $result = $clearh -> execute($menuid);
    return $self -> self_error("Deselection of menu failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return 1;
}


## @method $ get_menu(%args)
# Fetch the details of the specified menu. The supported args are:
#
# - `id`: The ID of the menu to fetch. If set, name is ignored.
# - `name`: The name of the menu to fetch; note that if multiple menus
#           have the same name, this will return the most recently
#           updated menu!
#
# @param args A hash, or reference to a hash, of arguments to search on.
# @return A reference to hash containing the menu data on success, a
#         reference to an empty hash if the menu isn't found, undef on
#         error.
sub get_menu {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    my $where  = "";
    my @params = ();

    if($args -> {"id"}) {
        $where = "`id` = ?";
        push(@params, $args -> {"id"});
    } elsif($args -> {"name"}) {
        $where = "`name` LIKE ?";
        push(@params, $args -> {"name"});
    } else {
        return $self -> self_error("get_menu called without valid arguments");
    }

    my $menuh = $self -> {"dbh"} -> prepare("SELECT *
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"menus"}."`
                                             WHERE $where
                                             ORDER BY `updated` DESC
                                             LIMIT 1");
    $menuh -> execute(@params)
        or return $self -> self_error("Lookup of menu failed: ".$self -> {"dbh"} -> errstr);

    return $menuh -> fetchrow_hashref() // {};
}


# ============================================================================
#  Menu activation

## @method $ set_active_menu($userid, $menuid)
# Set a menu as the active menu for the specified user. Note that this does not
# check that the user has edit permission on the menu - the caller is assumed
# to have verified this before calling this function.
#
# @param userid The ID of the user to set the active menu for.
# @param menuid The ID of the menu to set as the active menu. This can be undef
#               to unset the user's active menu.
# @return true on success, undef on error.
sub set_active_menu {
    my $self   = shift;
    my $userid = shift;
    my $menuid = shift;

    $self -> clear_error();

    my $activeh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"active"}."`
                                               (`user_id`, `menu_id`)
                                               VALUES(?, ?)
                                               ON DUPLICATE KEY UPDATE `menu_id` = VALUES(`menu_id`)");
    my $result = $activeh -> execute($userid, $menuid);
    return $self -> self_error("Insert of menu activation failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows changed when activating menu for user $userid.")
        if($result eq "0E0");

    return 1;
}


## @method $ get_active_menu($userid)
# Fetch the information about the user's currently active menu.
#
# @param userid The ID of the user to fetch the active menu for.
# @return A reference to a hash containing the active menu on success,
#         an empty hash if no active menu is set, undef on error.
sub get_active_menu {
    my $self   = shift;
    my $userid = shift;

    $self -> clear_error();

    my $activeh = $self -> {"dbh"} -> prepare("SELECT `menu_id`
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"active"}."`
                                               WHERE `user_id` = ?");
    $activeh -> execute($userid)
        or return $self -> self_error("Lookup of active menu failed: ".$self -> {"dbh"} -> errstr);

    # If there's no active menu, give up and return undef
    my $actrow = $activeh -> fetchrow_arrayref();
    return {}
        if(!$actrow || !$actrow -> [0]);

    # With an active menu, return the menu
    return $self -> get_menu($actrow -> [0]);
}


# ============================================================================
#  Recipe staging code

## @method $ stage_recipe($menuid,$recipeid)
# Add the specified recipe to the list of staged recipes for the menu. Note
# that this does not ensure that the specified recipe ID is not already
# staged for the menu, so multiple copies of the recipie can be staged.
#
# @param menuid   The ID of the menu to add the recipe to
# @param recipeid The ID of the recipe to add
# @return true on success, undef otherwise.
sub stage_recipe {
    my $self     = shift;
    my $menuid   = shift;
    my $recipeid = shift;

    $self -> clear_error();

    my $stageh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"staged"}."`
                                              (`menu_id`, `recipe_id`)
                                              VALUES(?, ?)");
    my $result = $newh -> execute($menuid, $recipeid);
    return $self -> self_error("Recipe staging failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows added when staging recipe.")
        if($result eq "0E0");

    return 1;
}


## @method $ unstage_recipe($stageid)
# Remove the specified staged recipe from the menu.
#
# @param stageid The ID of the staged recipe (not the recipe ID, the ID
#                of the row in the staged recipes table!)
# @return true on success, undef on error
sub unstage_recipe {
    my $self    = shift;
    my $stageid = shift;

    $self -> clear_error();

    my $delh = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"staged"}."`
                                            WHEN `id` = ?");
    my $result = $delh -> execute($stageid);
    return $self -> self_error("Recipe unstaging failed: ".$self -> {"dbh"} -> errstr)
        if(!$result);

    return $self -> self_error("No rows added when unstaging recipe.")
        if($result eq "0E0");

    return 1;
}


## @method $ get_staged_recipes($menuid)
# Fetch all the staged recipes for the specified menu. This will obtain
# the list of menus that have been staged for the specified menu.
#
# @param menuid The ID of the menu to fetch the staged recipes for.
# @return A reference to an array of recipe hashes on success, a reference
#         to an empty array if there are no staged recipies, and undef on
#         error.
sub get_staged_recipes {
    my $self   = shift;
    my $menuid = shift;

    $self -> clear_error();

    my $stagedh = $self -> {"dbh"} -> prepare("SELECT `s`.`id` AS `stage_id`, `r`.*
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"staged"}."` AS `s`
                                               LEFT JOIN `".$self -> {"settings"} -> {"database"} -> {"recipes"}."` AS `r`
                                                  ON `r`.`id` = `s`.`recipe_id`
                                               WHERE `s`.`menu_id` = ?
                                               ORDER BY `r`.`name`");
    $stagedh -> execute($menuid)
        or return $self -> self_error("Lookup of staged recipes failed: ".$self -> {"dbh"} -> errstr);

    # Obtain all the staged recipes
    return $stagedh -> fetchall_arrayref({});
}

1;