defmodule SMPPEX.Pdu.ItsSessionInfo do
  @moduledoc """
  Module for operating with ussd `deliver_sm` its_session_info parameter.
  """

  @type session_number :: pos_integer()
  @type sequence_number :: pos_integer()
  @type its_session_info :: <<_::16>>

  @spec encode(session_number, sequence_number) :: its_session_info

  @doc """
  Converts its_session_info session_number and sequence_number to octet string

  ## Example

      iex(1)> SMPPEX.Pdu.ItsSessionInfo.encode(8,1)
      <<08,01>>
  """
  def encode(session_number, sequence_number) when session_number < 256 and sequence_number < 256 do
    <<session_number::size(8), sequence_number::size(8)>>
  end

  @spec decode(its_session_info) :: {session_number, sequence_number}

  @doc """
  Converts octet_string from its_session_info tag to session_number and sequence_number

  ## Example

      iex(1)> SMPPEX.Pdu.ItsSessionInfo.decode(<<08,01>>)
      {8, 1}

  """
  def decode(<<session_number::size(8), sequence_number::size(8)>>) do
    {session_number, sequence_number}
  end
end
