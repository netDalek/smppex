defmodule SMPPEX.Protocol do

  alias SMPPEX.Protocol.CommandNames
  alias SMPPEX.Protocol.MandatoryFieldsSpecs
  alias SMPPEX.Protocol.MandatoryFieldsParser
  alias SMPPEX.Protocol.OptionalFieldsParser
  alias SMPPEX.Protocol.MandatoryFieldsBuilder
  alias SMPPEX.Protocol.OptionalFieldsBuilder
  alias SMPPEX.RawPdu
  alias SMPPEX.Pdu

  @pdus_with_status_dependant_body %{
     0x80000001 => true, # bind_transmitter_resp
     0x80000002 => true, # bind_receiver_resp
     0x80000009 => true, # bind_transceiver_resp
     0x80000004 => true # submit_sm_resp
  }

  @type error :: any
  @type pdu_parse_result :: {:pdu, Pdu.t} | {:unparsed_pdu, RawPdu.t, error}
  @type parse_result :: {:ok, nil, binary} | {:ok, pdu_parse_result, binary} | {:error, error}

  @spec parse(binary) :: parse_result

  def parse(bin) when byte_size(bin) < 4 do
    {:ok, nil, bin}
  end

  def parse(bin) do
    <<command_length :: big-unsigned-integer-size(32), rest :: binary >> = bin
    cond do
      command_length < 16 ->
        {:error, "Invalid PDU command_length #{inspect command_length}"}
      command_length <= byte_size(bin) ->
        body_length = command_length - 16
        << header :: binary-size(12), body :: binary-size(body_length), next_pdus :: binary >> = rest
        {:ok, parse_pdu(header, body), next_pdus}
      true ->
        {:ok, nil, bin}
    end
  end

  defp parse_pdu(header, body) do
    header = parse_header(header)
    raw_pdu = RawPdu.new(header, body)
    case CommandNames.name_by_id(RawPdu.command_id(raw_pdu)) do
      {:ok, name} -> parse_body(name, raw_pdu)
      :unknown -> {:unparsed_pdu, raw_pdu, "Unknown command_id"}
    end
  end

  defp parse_header(<<command_id :: big-unsigned-integer-size(32), command_status :: big-unsigned-integer-size(32), sequence_number :: big-unsigned-integer-size(32)>>) do
    {command_id, command_status, sequence_number}
  end

  defp parse_body(command_name, raw_pdu) do
    case parse_mandatory_fields(command_name, raw_pdu) do
      {:ok, fields, rest} ->
        case OptionalFieldsParser.parse(rest) do
          {:ok, tlvs} ->
            {:pdu, Pdu.new(RawPdu.header(raw_pdu), fields, tlvs)}
          {:error, error} -> {:unparsed_pdu, raw_pdu, error}
        end
      {:error, error} -> {:unparsed_pdu, raw_pdu, error}
    end
  end

  defp parse_mandatory?(raw_pdu) do
    command_status = RawPdu.command_status(raw_pdu)
    command_id = RawPdu.command_id(raw_pdu)
    (command_status == 0) or (not Map.has_key?(@pdus_with_status_dependant_body, command_id))
  end

  defp parse_mandatory_fields(command_name, raw_pdu) do
    case parse_mandatory?(raw_pdu) do
      true ->
        spec = MandatoryFieldsSpecs.spec_for(command_name)
        raw_pdu |> RawPdu.body |> MandatoryFieldsParser.parse(spec)
      false ->
        {:ok, %{}, RawPdu.body(raw_pdu) }
    end
  end

  @type build_result :: {:ok, binary} | {:error, error}

  @spec build(Pdu.t) :: build_result

  def build(pdu) do
    case build_header(pdu) do
      {:ok, mandatory_specs, header_bin} -> build_body(pdu, header_bin, mandatory_specs)
      {:error, error} -> {:error, {"Error building header part", error}}
    end
  end

  defp build_body(pdu, header_bin, mandatory_specs) do
    case build_mandatory_fields(pdu, mandatory_specs) do
      {:ok, mandatory_bin} ->
        case build_optional_fields(pdu) do
          {:ok, optional_bin} -> {:ok, concat_pdu_binary_parts(header_bin, mandatory_bin, optional_bin)}
          {:error, error} -> {:error, {"Error building optional field part", error}}
        end
      {:error, error} -> {:error, {"Error building mandatory field part", error}}
    end
  end

  defp build_header(pdu) do
    {command_id, command_status, sequence_number} = {
      Pdu.command_id(pdu),
      Pdu.command_status(pdu),
      Pdu.sequence_number(pdu)
    }
    case CommandNames.name_by_id(command_id) do
      {:ok, name} -> {:ok,
        MandatoryFieldsSpecs.spec_for(name),
        <<command_id :: big-unsigned-integer-size(32), command_status :: big-unsigned-integer-size(32), sequence_number :: big-unsigned-integer-size(32)>>}
      :unknown -> {:error, "Unknown command_id #{inspect command_id}"}
    end
  end

  defp build_mandatory?(pdu) do
    command_status = Pdu.command_status(pdu)
    command_id = Pdu.command_id(pdu)
    (command_status == 0) or (command_status == nil) or (not Map.has_key?(@pdus_with_status_dependant_body, command_id))
  end

  defp build_mandatory_fields(pdu, specs) do
    case build_mandatory?(pdu) do
      true -> pdu |> Pdu.mandatory_fields |> MandatoryFieldsBuilder.build(specs)
      false -> {:ok, <<>>}
    end
  end

  defp build_optional_fields(pdu) do
    pdu |> Pdu.optional_fields |> OptionalFieldsBuilder.build
  end

  defp concat_pdu_binary_parts(header, mandatory, optional) do
    pdu_data = [header, mandatory, optional] |> List.flatten |> Enum.join
    size = byte_size(pdu_data) + 4
    << size :: big-unsigned-integer-size(32), pdu_data :: binary >>
  end

end
