# Models

In your `Breakfast` class, the properties are defined with `get;` only, which
means they are read-only properties. Once they are set (which happens in the
constructor in this case), they cannot be changed. This is often used to create
immutable objects, which can be beneficial for maintaining data integrity and
thread safety.

Here's an example:

```csharp
public class Breakfast
{
    public Guid Id { get; }

    public Breakfast(Guid id)
    {
        Id = id;
    }
}

var breakfast = new Breakfast(Guid.NewGuid());
// breakfast.Id = Guid.NewGuid(); // This would cause a compile error because Id is read-only
```

If you define properties with `get; set;`, they are read-write properties. This
means you can change their values anytime after the object is created. Here's an
example:

```csharp
public class Breakfast
{
    public Guid Id { get; set; }
}

var breakfast = new Breakfast();
breakfast.Id = Guid.NewGuid(); // This is allowed because Id is a read-write property
```

> If you want to ensure that an object's state cannot be changed after it's
> created, use read-only properties. If you need to be able to change an
> object's state, use read-write properties.
