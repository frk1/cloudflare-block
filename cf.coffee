#!/usr/bin/env coffee
_             = require 'lodash'
R             = require 'ramda'
ip            = require 'ip'
Promise       = require "bluebird"
CloudFlareAPI = require 'cloudflare4'
countries     = require('country-data').countries

dns = Promise.promisifyAll require("dns")
cf = new CloudFlareAPI
  email: 'YOUR_MAIL'
  key:   'YOUR_KEY'
  autoPagination: true
  autoPaginationConcurrency: 4

COUNTRIES_ALLOWED = [
  'DE'
  'AT'
  'CH'
]

airvpn_exit_ips_country = (code) ->
  dns.resolveAsync "#{_.toLower code}.all.vpn.airdns.org"
  .then R.map (e) -> ip.fromLong ip.toLong(e)+1

airvpn_exit_ips_servers = (names) ->
  Promise.map names, (name) ->
    dns.resolveAsync "#{name}.airservers.org"
    .then (res) ->
      {name: name, res: res.map (e) -> ip.fromLong ip.toLong(e)+1}
    .catch ->
      console.error "Error trying to resolve server '#{name}'"
      null
  .then _.compact

delete_existing_rules = ->
  cf.userFirewallAccessRuleGetAll()
  .map (rule) ->
    cf.userFirewallAccessRuleDestroy rule.id
    .then ->
      console.log "Deleted rule '#{rule.id}'"

delete_country_blocks = ->
  cf.userFirewallAccessRuleGetAll configuration_target: 'country'
  .map (rule) ->
    cf.userFirewallAccessRuleDestroy rule.id
    .then ->
      console.log "Deleted rule '#{rule.id}', Country '#{rule.configuration.value}'"

block_countries = (countries) ->
  Promise.map countries, (c) ->
    cf.userFirewallAccessRuleNew
      mode: 'challenge'
      configuration:
        target: 'country'
        value: c
    .then ->
      console.log "#{c}: Rule created!"
    .catch ->

block_bad_countries = ->
  block_countries R.difference(R.pluck('alpha2', countries.all), COUNTRIES_ALLOWED)

whitelist_ips = (ips, comment) ->
  Promise.map ips, (i) ->
    cf.userFirewallAccessRuleNew
      mode: 'whitelist'
      configuration:
        target: 'ip'
        value: i
      notes: comment
    .then ->
      console.log "Whitelisted '#{i}' (#{comment})"
    .catch (err) ->
      console.error "Failed to whitelist '#{i}' (#{comment}): #{err}"

whitelist_airvpn_country = (c) ->
  airvpn_exit_ips_country c
  .then (ips) ->
    whitelist_ips ips, "AirVPN #{_.toUpper c}"

whitelist_airvpn_servers = (names) ->
  airvpn_exit_ips_servers names
  .then (query) ->
    Promise.map query, ({name, res}) ->
      whitelist_ips res, "AirVPN #{name}"

# --------------------------------------------------------------------------------------------------

delete_existing_rules()
.then ->
  block_bad_countries()
.then ->
  Promise.map ['nl', 'be', 'ch', 'no'], whitelist_airvpn_country
.then ->
  whitelist_airvpn_servers ['Mirach', 'Capricornus']
.then ->
  console.log "Done!"
