class McpController < ApplicationController
  skip_before_action :verify_authenticity_token

  def proxy
    # Forward the JSON-RPC request to the stdio MCP server
    request_json = request.body.read

    mcp_server_path = Rails.root.join('bin', 'mcp-server')

    # Spawn MCP server and send request via stdin
    response_json = IO.popen(['ruby', mcp_server_path.to_s], 'r+') do |io|
      io.puts request_json
      io.close_write
      io.read.lines.reject { |line| line.include?('MCP Server running') }.join
    end

    render json: JSON.parse(response_json), status: :ok
  rescue JSON::ParserError => e
    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: { code: -32700, message: "Parse error: #{e.message}" }
    }, status: :bad_request
  rescue => e
    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: { code: -32603, message: "Internal error: #{e.message}" }
    }, status: :internal_server_error
  end
end
