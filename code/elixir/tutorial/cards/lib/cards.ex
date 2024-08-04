defmodule Cards do
  @moduledoc """
  Documentation for `Cards`.
  Provides functions for working with a deck of cards.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Cards.hello()
      :world

  """
  def hello do
    :world
  end

  @doc """
   Create a deck of cards.
  """
  def create_deck do
    values = [
      "Ace",
      "Two",
      "Three",
      "Four",
      "Five",
      "Six",
      "Seven",
      "Eight",
      "Nine",
      "Ten",
      "Jack",
      "Queen",
      "King"
    ]

    suits = [
      "Hearts",
      "Diamonds",
      "Clubs",
      "Spades"
    ]

    ## Soulution 1
    # cards =
    #   for suit <- suits do
    #     for value <- values do
    #       "#{value} of #{suit}"
    #     end
    #   end

    # List.flatten(cards)

    ## Soulution 2
    for suit <- suits, value <- values do
      "#{value} of #{suit}"
    end
  end

  @doc """
  Shuffle a deck of cards.

  ## Examples

      iex> deck = Cards.create_deck()
      iex> shuffled_deck = Cards.shuffle(deck)
      iex> Enum.sort(deck) == Enum.sort(shuffled_deck)
      true

  """
  def shuffle(deck) do
    Enum.shuffle(deck)
  end

  @doc """
  Check if a deck of cards contains a specific card.

  ## Examples

      iex> deck = Cards.create_deck
      iex> Cards.contains?(deck, "Ace of Hearts")
      true

  """
  def contains?(deck, card) do
    Enum.member?(deck, card)
  end

  @doc """
  Deal a hand of cards from a deck.

  ## Examples

      iex> deck = Cards.create_deck
      iex> hand = Cards.deal(deck, 5)
      iex> Enum.count(hand)
      5

  """
  def deal(deck, hand_size) do
    # {hand, _} = Enum.split(deck, hand_size)
    # hand

    Enum.take(deck, hand_size)
  end

  @doc """
  Save a deck of cards to a file.

  ## Examples

      iex> deck = Cards.create_deck()
      iex> Cards.save(deck, "deck.dat")
      :ok
      iex> File.read!("deck.dat") == :erlang.term_to_binary(deck)
      true

  """
  def save(deck, file_name) do
    binary = :erlang.term_to_binary(deck)
    File.write!(file_name, binary)
  end

  @doc """
  Load a deck of cards from a file.

  ## Examples

      iex> deck = Cards.create_deck()
      iex> Cards.save(deck, "deck.dat")
      :ok
      iex> loaded_deck = Cards.load("deck.dat")
      iex> loaded_deck == deck
      true

  """
  def load(file_name) do
    # {status, binary} = File.read(file_name)

    # case status do
    #   :ok -> :erlang.binary_to_term(binary)
    #   _ -> "File not found"
    # end

    case File.read(file_name) do
      {:ok, binary} -> :erlang.binary_to_term(binary)
      {:error, _reason} -> "File not found"
    end
  end

  @doc """
  Create a hand of cards.

  ## Examples

      iex> hand = Cards.create_hand(5)
      iex> length(hand)
      5
      iex> Enum.all?(hand, &(&1 in Cards.create_deck()))
      true

  """
  def create_hand(hand_size) do
    # deck = Cards.create_deck()
    # deck = Cards.shuffle(deck)
    # hand = Cards.deal(deck, hand_size)

    create_deck()
    |> shuffle()
    |> deal(hand_size)
  end
end
