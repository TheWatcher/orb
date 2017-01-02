#!/usr/bin/perl -w

use v5.14;
use strict;
use lib qw(/var/www/webperl);
use lib qw(../modules);

use DBI;
use Webperl::Logger;
use Webperl::ConfigMicro;
use ORB::System;
use Data::Dumper;


## @fn $ get_source_recipeids($dbh, $settings, $logger)
# Fetch a list of recipie IDs in the source ORB database.
#
# @param dbh      A reference to a database handle to issue queries through.
# @param settings A reference to the system settings object
# @param logger   A reference to a global logger object
# @return A reference to an array of recipe IDs.
sub get_source_recipeids {
    my $dbh      = shift;
    my $settings = shift;
    my $logger   = shift;

    my $query = $dbh -> prepare("SELECT `id`
                                 FROM `".$settings -> {"database"} -> {"recipes"}."`
                                 ORDER BY `id`");
    $query -> execute()
        or $logger -> die_log(undef, "Unable to fetch source recipe list: ".$dbh -> errstr);

    # Flatten the result of fetchall_arrayref so that we return a reference to
    # an array of recipie IDs rather than a reference to an array of arrayrefs
    return [ map { $_ -> [0] } @{$query -> fetchall_arrayref([0])} ];
}


## @fn $ get_source_recipe_relations($recipe, $dbh, $settings, $logger)
# Fetch the ingredients and tags from the source database and store them in the
# provided recipe hash.
#
# @param recipe   A reference to a recipe hash
# @param dbh      A reference to a database handle to issue queries through.
# @param settings A reference to the system settings object
# @param logger   A reference to a global logger object
# @return A reference to a hash containing the recipe data.
sub get_source_recipe_relations {
    my $recipe   = shift;
    my $dbh      = shift;
    my $settings = shift;
    my $logger   = shift;

    # Fetch all the recipe ingredients - the ordering is implicit in the IDs in
    # the old ORB setup
    my $ingredh = $dbh -> prepare("SELECT `r`.*, `i`.`name`, `p`.`name` AS `prep`
                                   FROM `".$settings -> {"database"} -> {"recipeing"}."` AS `r`
                                   LEFT JOIN `".$settings -> {"database"} -> {"ingredients"}."` AS `i`
                                       ON `i`.`id` = `r`.`ingredient`
                                   LEFT JOIN `".$settings -> {"database"} -> {"prep"}."` AS `p`
                                       ON `p`.`id` = `r`.`prepid`
                                   WHERE `r`.`recipeid` = ?
                                   ORDER BY `r`.`id`");
    $ingredh -> execute($recipe -> {"id"})
        or $logger -> die_log(undef, "Unable to fetch source ingredient list: ".$dbh -> errstr);

    my @ingredients;
    # construct a list of the ingredients
    while(my $ingred = $ingredh -> fetchrow_hashref()) {
        push(@ingredients, $ingred);
    }

    # A reference to the ingredients has to go into the recipe
    $recipe -> {"ingredients"} = \@ingredients;

    # Now build the tags
    my $tagh = $dbh -> prepare("SELECT `t`.`name`
                                FROM `".$settings -> {"database"} -> {"recipetags"}."` AS `r`,
                                     `".$settings -> {"database"} -> {"tags"}."` AS `t`
                                WHERE `r`.`recipeid` = ?
                                AND `t`.`id` = `r`.`tagid`");
    $tagh -> execute($recipe -> {"id"})
        or $logger -> die_log(undef, "Unable to fetch source tag list: ".$dbh -> errstr);

    # Build up the tags in one string
    my @tags = map { $_ -> [0] } @{$tagh -> fetchall_arrayref([0])};
    $recipe -> {"tags"} = join(",", @tags);

    return $recipe;
}


## @fn $ get_source_recipe($recipieid, $dbh, $settings, $logger)
# Fetch the data for a specified recipe in the source ORB database.
#
# @param recipeid The ID of the recipie to fetch the data for.
# @param dbh      A reference to a database handle to issue queries through.
# @param settings A reference to the system settings object
# @param logger   A reference to a global logger object
# @return A reference to a hash containing the recipe data
sub get_source_recipe {
    my $recipeid = shift;
    my $dbh      = shift;
    my $settings = shift;
    my $logger   = shift;

    my $lookup = $dbh -> prepare("SELECT `r`.*, `s`.`name` AS `statusname`, `t`.`name` AS `typename`, `c`.`username` AS `createuser`, `u`.`username` AS `updateruser`
                                  FROM `".$settings -> {"database"} -> {"recipes"}."` AS `r`
                                  LEFT JOIN `".$settings -> {"database"} -> {"states"}."` AS `s`
                                      ON `s`.`id` = `r`.`status`
                                  LEFT JOIN `".$settings -> {"database"} -> {"types"}."`  AS `t`
                                      ON `t`.`id` = `r`.`type`
                                  LEFT JOIN `".$settings -> {"database"} -> {"users"}."` AS `c`
                                      ON `c`.`user_id` = `r`.`creator`
                                  LEFT JOIN `".$settings -> {"database"} -> {"users"}."` AS `u`
                                      ON `u`.`user_id` = `r`.`updater`
                                  WHERE `r`.`id` = ?");
    $lookup -> execute($recipeid)
        or $logger -> die_log(undef, "Unable to fetch source recipe: ".$dbh -> errstr);

    my $recipe = $lookup -> fetchrow_hashref()
        or $logger -> die_log(undef, "Request for non-existent recipe $recipeid");

    # pull in the extra data - ingredients and tags
    return get_source_recipe_relations($recipe, $dbh, $settings, $logger);
}


## @fn $ convert_user($username, $dbh, $settings, $logger)
# Convert the username from the old system into a user Id in the new.
#
# @param username The name of the user to get an ID for
# @param dbh      A reference to a database handle to issue queries through.
# @param settings A reference to the system settings object
# @param logger   A reference to a global logger object
# @return The ID of the new user
sub convert_user {
    my $username = shift;
    my $dbh      = shift;
    my $settings = shift;
    my $logger   = shift;

    my $lookup = $dbh -> prepare("SELECT `user_id`
                                  FROM `".$settings -> {"database"} -> {"users"}."`
                                  WHERE `username` LIKE ?");
    $lookup -> execute($username)
        or $logger -> die_log(undef, "Unable to seach for updated user: ".$dbh -> errstr);

    my $user = $lookup -> fetchrow_arrayref()
        or $logger -> die_log(undef, "Unable to locate match for user '$username'");

    return $user -> [0];
}


## @fn $ convert_recipe($recipe, $dbh, $settings, $logger)
# Given a legacy ORB recipe data hash, update the fields to be suitable to pass
# to ORB::System::Recipe::create()
#
# @param recipe   A reference to a recipe hash
# @param dbh      A reference to a database handle to issue queries through.
# @param settings A reference to the system settings object
# @param logger   A reference to a global logger object
# @return A reference to a hash containing the updated recipe data.
sub convert_recipe {
    my $recipe   = shift;
    my $dbh      = shift;
    my $settings = shift;
    my $logger   = shift;

    # Fix up recipe fields
    # Created fields should use last update on the legacy system.
    $recipe -> {"creatorid"} = convert_user($recipe -> {"updateruser"}, $dbh, $settings, $logger);
    $recipe -> {"created"}   = $recipe -> {"updated"};

    # And fix up fields that need to do name mapping
    $recipe -> {"type"}   = $recipe -> {"typename"};
    $recipe -> {"status"} = $recipe -> {"statusname"};

    # And go through the list of ingredients tweaking as needed
    foreach my $ingred (@{$recipe -> {"ingredients"}}) {
        # Fix the moronic handling of separators in the original version
        if($ingred -> {"units"} eq "Separator") {
            $ingred -> {"units"} = '';
            $ingred -> {"name"} = $ingred -> {"separator"};
            $ingred -> {"separator"} = 1;
        } else {
            $ingred -> {"separator"} = 0;
        }
    }

    return $recipe;
}


my $logger = Webperl::Logger -> new()
        or die "FATAL: Unable to create logger object\n";

my $legacycfg = Webperl::ConfigMicro -> new("../config/legacy.cfg")
    or $logger -> die_log(undef, "Unable to open legacy config file: ".$Webperl::SystemModule::errstr);

my $targetcfg = Webperl::ConfigMicro -> new("../config/config.cfg")
    or $logger -> die_log(undef, "Unable to open target config file: ".$Webperl::SystemModule::errstr);

my $olddbh = DBI->connect($legacycfg -> {"database"} -> {"database"},
                          $legacycfg -> {"database"} -> {"username"},
                          $legacycfg -> {"database"} -> {"password"},
                          { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 })
    or $logger -> die_log(undef, "Unable to connect to old database: ".$DBI::errstr);

my $newdbh = DBI->connect($targetcfg -> {"database"} -> {"database"},
                          $targetcfg -> {"database"} -> {"username"},
                          $targetcfg -> {"database"} -> {"password"},
                          { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 })
    or $logger -> die_log(undef, "Unable to connect to new database: ".$DBI::errstr);

my $system = ORB::System -> new(dbh      => $newdbh,
                                settings => $targetcfg,
                                logger   => $logger)
    or $logger -> die_log(undef, "Unable to create system object: ".$Webperl::SystemModule::errstr);

$system -> init()
    or $logger -> die_log(undef, $system -> errstr());

my $rows = get_source_recipeids($olddbh, $legacycfg, $logger);

foreach my $recipeid (@{$rows}) {
    print "Migrating $recipeid: ";
    my $recipe = get_source_recipe($recipeid, $olddbh, $legacycfg, $logger);
    print $recipe -> {"name"}."... ";
    $recipe = convert_recipe($recipe, $newdbh, $targetcfg, $logger);

    my $newid = $system -> {"recipe"} -> create($recipe)
        or $logger -> die_log(undef, "Addition failed: ".$system -> {"recipe"} -> errstr());

    print "$newid\n";
}
print "Done\n";
