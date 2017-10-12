defmodule SMPPEX.Protocol.OptionalFieldsParser do
  @moduledoc false

  alias SMPPEX.Protocol.Unpack
  alias SMPPEX.Protocol.TlvFormat

  @type parse_result :: {:ok, map} | {:error, reason :: term}

  @spec parse(binary) :: parse_result

  def parse(bin), do: parse(bin, Map.new)

  defp parse(<<>>, parsed_fields) do
    {:ok, parsed_fields}
  end

  defp parse(bin, parsed_fields) do
    case Unpack.tlv(bin) do
      {:ok, {tag, value}, rest} ->
        case parse_format(tag, value) do
          {:ok, parsed} ->
            parse(rest, Map.put(parsed_fields, tag, parsed))
          {:error, error} -> {:error, {"Invalid format for tlv #{inspect tag}", error}}
        end
      {:error, _} = err -> err
    end
  end

  defp parse_format(tag, value) do
    case TlvFormat.format_by_id(tag) do
      {:ok, format} -> parse_known_tlv(value, format)
      :unknown -> {:ok, value} # unknown tlvs are always valid
    end
  end

  defp parse_known_tlv(value, {:integer, size}) do
    bit_length = size * 8
    case value do
      <<int :: big-unsigned-integer-size(bit_length)>> -> {:ok, int}
      _ -> {:error, "Invalid integer"}
    end
  end

  defp parse_known_tlv(value, {:c_octet_string, {:max, size}}) do
    case Unpack.c_octet_string(value, {:max, size}) do
      {:ok, str, ""} -> {:ok, str}
      _ -> {:error, "Invalid c_octet_string"}
    end
  end

  defp parse_known_tlv(value, {:octet_string, size}) when is_integer(size) do
    case Unpack.octet_string(value, size) do
      {:ok, value, <<>>} -> {:ok, value}
      _ -> {:error, "Invalid octet_string"}
    end
  end
  
  defp parse_known_tlv(value, {:octet_string, {from, to}}) when is_integer(from) and is_integer(to) do
    case Unpack.octet_string(value, {from, to}) do
      {:ok, value} -> {:ok, value}
      _ -> {:error, "Invalid octet_string"}
    end
  end

end
