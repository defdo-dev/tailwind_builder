ExUnit.start()

# Define the behavior for ExAws.Request.HttpClient
# defmodule ExAws.Request.HttpClient do
#   @callback request(
#               method :: atom,
#               url :: binary,
#               body :: binary,
#               headers :: [{binary, binary}],
#               opts :: keyword
#             ) :: {:ok, %{status_code: pos_integer, body: term}} | {:error, term}
# end

# Define and configure the mock
Mox.defmock(ExAws.Request.HttpMock, for: ExAws.Request.HttpClient)
Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)
