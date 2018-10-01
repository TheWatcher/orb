# @file
# This file contains the implementation of the API class
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

## @class
package ORB::API;

use strict;
use experimental 'smartmatch';
use parent qw(ORB);
use Webperl::Utils qw(hash_or_hashref);
use DateTime;
use MIME::Base64;
use JSON;
use v5.12;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Overloaded constructor for the API
#
# @param args A hash of values to initialise the object with. See the Block docs
#             for more information.
# @return A reference to a new ORB::API object on success, undef on error.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new( timefmt => '%a, %d %b %Y %H:%M:%S %Z',
                                         @_)
        or return undef;

    return $self;
}


# ============================================================================
#  Support functions

## @method private $ _show_api_docs()
# Redirect the user to a Swagger-generated API documentation page.
# Note that this function will never return.
sub _show_api_docs {
    my $self = shift;

    $self -> log("api:docs", "Sending user to API docs");

    my ($host) = $self -> {"settings"} -> {"config"} -> {"httphost"} =~ m|^https?://([^/]+)|;
    return $self -> {"template"} -> load_template("api/docs.tem", { "%(host)s" => $host });
}


# ============================================================================
#  API functions

## @method private $ _build_token_response()
# Generate an API token for the currently logged-in user.
#
# @api GET /token
#
# @return A reference to a hash containing the API response data.
sub _build_token_response {
    my $self = shift;

    return $self -> api_response($self -> api_errorhash('permission_error',
                                                        "You do not have permission to request tokens"))
        unless($self -> check_permission('api.token'));

    if($self -> {"cgi"} -> request_method() eq "GET") {
        $self -> log("api:token", "Generating new API token for user");

        my $token = $self -> api_token_generate($self -> {"session"} -> get_session_userid())
            or return $self -> api_errorhash('internal_error', $self -> errstr());

        return { "token" => $token };
    }

    return $self -> api_errorhash("bad_request", $self -> {"template"} -> replace_langvar("API_BAD_REQUEST"));
}


## @method private $ _build_ingredients_response()
# Fetch the list of igredients in the system, limited to 100 possible matches
# at a time if doing a search. By default this will return a list of all
# ingredients in the system as an array of hashes containing `id` and `value`
# keys, where `id` is the ID of the ingredient, and `value` is the name of the
# ingredient. If a 'term' query parameter has been set when invoking the API,
# that is used to search through the ingredients in the system to produce a
# list of at most 100 ingredients that include the term.
#
# @api GET /ingredients
#
# @return A reference to a hash containing the API response data.
sub _build_ingredients_response {
    my $self = shift;

    # If the user is doing a GET, they're listing ingredients
    if($self -> {"cgi"} -> request_method() eq "GET") {
        my ($term, $error) = $self -> validate_string("term", { required => 0,
                                                                default  => undef,
                                                                nicename => "term" });
        $self -> api_errorhash("bad_request",
                               $self -> {"template"} -> replace_langvar("API_BAD_REQUEST_DATA",
                                                                        {
                                                                            "%(reason)s" => $error
                                                                        }))
            if($error);

        $self -> log("api:ingredients", "Fetching ingredients - term = ".($term // "not set"));

        # If no term is set, return ALL THE THINGS
        return $self -> {"system"} -> {"entities"} -> {"ingredients"} -> find(term  => $term,
                                                                              as    => "value",
                                                                              limit => $term ? 100 : undef);
    }

    return $self -> api_errorhash("bad_request", $self -> {"template"} -> replace_langvar("API_BAD_REQUEST"));
}


## @method private $ _build_tags_response()
# Fetch the list of tags defined in the system. This will return the list of
# tags as an array of hashes, where each tag is a hash with the keys `id`
# for the tag ID, and `text` for the tag name. If an optional `term` parameter
# is set when invoking the API, this will return at most 100 tags that include
# the term specified.
#
# @api GET /tags
#
# @return A reference to a hash containing the API response data.
sub _build_tags_response {
    my $self = shift;

    # If the user is doing a GET, they're listing tags
    if($self -> {"cgi"} -> request_method() eq "GET") {
        my ($term, $error) = $self -> validate_string("term", { required => 0,
                                                                default  => undef,
                                                                nicename => "term" });
        $self -> api_errorhash("bad_request",
                               $self -> {"template"} -> replace_langvar("API_BAD_REQUEST_DATA",
                                                                        {
                                                                            "%(reason)s" => $error
                                                                        }))
            if($error);

        $self -> log("api:tags", "Fetching tags - term = ".($term // "not set"));

        return { results => $self -> {"system"} -> {"entities"} -> {"tags"} -> find(term => $term,
                                                                                    id   => "name",
                                                                                    as   => "text") };
    }

    return $self -> api_errorhash("bad_request", $self -> {"template"} -> replace_langvar("API_BAD_REQUEST"));
}


## @method private $ _build_recipes_response()
# Fetch the list of recipes in the system, filtered by name.
#
# @api GET /recipes
#
# @return A reference to a hash containing the API response data.
sub _build_recipes_response {
    my $self = shift;

    if($self -> {"cgi"} -> request_method() eq "GET") {
        my ($name, $error) = $self -> validate_string("name", { required => 1,
                                                                default  => undef,
                                                                nicename => "name" });
        $self -> api_errorhash("bad_request",
                               $self -> {"template"} -> replace_langvar("API_BAD_REQUEST_DATA",
                                                                        {
                                                                            "%(reason)s" => $error
                                                                        }))
            if($error);

        $self -> log("api:recipes", "Fetching recipe - name = ".($name // "not set"));

        return { results => $self -> {"system"} -> {"recipe"} -> find(name => $name) };
    }

    return $self -> api_errorhash("bad_request", $self -> {"template"} -> replace_langvar("API_BAD_REQUEST"));
}


# ============================================================================
#  Interface functions

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the compose page, including any errors or user feedback.
#
# @capabilities api.use
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # Session check can be done by anyone
        return $self -> api_response($self -> _build_session_response())
            if($apiop eq "session");

        $self -> api_token_login();

        # General API permission check - will block anonymous users at a minimum
        return $self -> api_response($self -> api_errorhash('permission_error',
                                                            "You do not have permission to use the API"))
            unless($self -> check_permission('api.use'));

        # API call - dispatch to appropriate handler.
        given($apiop) {
            when("ingredients") { return $self -> api_response($self -> _build_ingredients_response()); }
            when("recipes")     { return $self -> api_response($self -> _build_recipes_response());     }
            when("tags")        { return $self -> api_response($self -> _build_tags_response());        }
            when("token")       { return $self -> api_response($self -> _build_token_response());       }

            when("")            { return $self -> _show_api_docs(); }

            default {
                return $self -> api_response($self -> api_errorhash('bad_op',
                                                                    $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        return $self -> _show_api_docs();
    }
}



1;