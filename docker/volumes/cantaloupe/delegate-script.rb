##
# This script is released under the CC0 1.0 Universal (CC0 1.0) Public Domain
# Dedication. It has been developed to access the Supabase Storage API with 
# Cantaloupe. API access is preceded by pre-authorization, as Cantaloupe may load
# resources from the cache. In these cases, unauthorized access to protected
# resources is prevented by always checking whether the request to the storage
# API is authorized.
# 
# The script has also been tested for access to resources via Httpsource that
# do not require any authorization.
#
# This version of the script works with Cantaloupe version >= 5.
require 'net/http'
require 'uri'

class CustomDelegate
  attr_accessor :context

  def initialize
    # Set @url_prefix to your desired base URL
    @url_prefix = ENV['CANTALOUPE_HTTPSOURCE_BASICLOOKUPSTRATEGY_URL_PREFIX']
  end

  # Performs pre-authorization for the request.
  # If not used, resources will be loaded from cache without authorization.
  #
  # @param options [Hash] Options for pre-authorization (not used).
  # @return [Boolean] True if the resource is accessible; false otherwise.
  def pre_authorize(options = {})
    puts "Pre-authorizing request"
    # Check if the resource is accessible at the given endpoint
    return resource_accessible
  end

  def authorize(options = {})
    puts "Authorizing request"
    true
  end

  def source(options = {})
  end

  def extra_iiif2_information_response_keys(options = {})
    {}
  end

  def extra_iiif3_information_response_keys(options = {})
    {}
  end
  
  # Retrieves resource information for the HTTP source.
  #
  # @param options [Hash] Options for retrieving resource information (not used).
  # @return [Hash] Resource information including URI, headers, and send_head_request flag.
  def httpsource_resource_info(options = {})
    puts "Getting resource info for identifier: #{context['identifier']}"
    # Construct the URI using @url_prefix and the requested identifier
    if @url_prefix
      identifier = context['identifier']
      if identifier
        uri = "#{@url_prefix}#{identifier}"
        puts "Constructed URI: #{uri}"

        # Extract bearer token from request headers
        bearer_token = extract_bearer_token(context['request_headers'])

        # Include bearer token in headers
        headers = {
          "Authorization" => "Bearer #{bearer_token}"
        }

        return {
          'uri' => uri,
          'headers' => headers,
          'send_head_request' => true
        }

      else
        puts "Identifier is nil"
        nil
      end
    else
      puts "@url_prefix is nil"
      nil
    end
  end

  private
  
  # Extracts the bearer token from the request headers.
  #
  # @param request_headers [Hash] Request headers.
  # @return [String, nil] Bearer token if present; nil otherwise.
  def extract_bearer_token(request_headers)
    authorization_header = request_headers['Authorization']
    if authorization_header && authorization_header.start_with?('Bearer ')
      return authorization_header.split(' ').last
    end
    # Return nil if no bearer token found
    nil
  end

  # Checks if the resource is accessible.
  #
  # This is a lightweight method used to determine if the requested resource
  # is accessible at the given endpoint. It performs a HEAD request to the
  # endpoint URI with the provided bearer token, if available, to determine
  # accessibility.
  #
  # @return [Boolean] True if the resource is accessible; false otherwise.
  def resource_accessible
    # Check if the bearer token is present in the context
    bearer_token = extract_bearer_token(context['request_headers'])

    # Attempt to access the resource using the provided token
    uri = URI(@url_prefix)
    uri.path += "/#{context['identifier']}" if context['identifier']
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Head.new(uri)
    request['Authorization'] = "Bearer #{bearer_token}" if bearer_token

    response = http.request(request)

    # Return true if the response code indicates success (2xx status code)
    return response.code.start_with?('2')
  end
end