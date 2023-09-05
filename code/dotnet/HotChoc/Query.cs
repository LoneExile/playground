public class Query
{
    public string Hello(string name = "worldddd")
    {
        return $"Hello, {name}!";
    }

    public IEnumerable<Book> GetBooks()
    {
        Author author = new("George Orwell");
        yield return new Book("1984", author);
        yield return new Book("Animal Farm", author);
    }

}

public record Author(string Name);

public record Book(string Title, Author Author);

/*
{
    hello(name:"moo")
    books{
      title
      author{
        name
      }
    }
}
*/
