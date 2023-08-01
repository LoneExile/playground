// using System.ComponentModel.DataAnnotations;
using BuberBreakfast.ServicesErrors;
using ErrorOr;

namespace BuberBreakfast.Models;

public class Breakfast
{
    public const int MaxNameLength = 50;
    public const int MinNameLength = 5;

    public const int MaxDescriptionLength = 500;
    public const int MinDescriptionLength = 5;

    public Guid Id { get; }

    public string Name { get; }
    // [MinLength(3), MaxLength(50)] public string Name { get; }
    // NOTE: in the above line, the [MinLength(3), MaxLength(50)] is a data annotation
    // that is used by the Entity Framework to create a database schema

    public string Description { get; }
    public DateTime StartDateTime { get; }
    public DateTime EndDateTime { get; }
    public DateTime LastModifiedDateTime { get; }
    public List<string> Savory { get; }
    public List<string> Sweet { get; }

    private Breakfast(
        Guid id,
        string name,
        string description,
        DateTime startDateTime,
        DateTime endDateTime,
        DateTime lastModifiedDateTime,
        List<string> savory,
        List<string> sweet)
    {
        Id = id;
        Name = name;
        Description = description;
        StartDateTime = startDateTime;
        EndDateTime = endDateTime;
        LastModifiedDateTime = lastModifiedDateTime;
        Savory = savory;
        Sweet = sweet;
    }

    public static ErrorOr<Breakfast> Create(
        string name,
        string description,
        DateTime startDateTime,
        DateTime endDateTime,
        List<string> savory,
        List<string> sweet,
        Guid? id = null)
    {
        List<Error> errors = new();
        if (name.Length is < MinNameLength or > MaxNameLength)
        {
            errors.Add(Errors.Breakfast.InvalidName);
        }

        if (description.Length is < MinDescriptionLength or > MaxDescriptionLength)
        {
            errors.Add(Errors.Breakfast.InvalidDescription);
        }

        if (errors.Any())
        {
            return errors;
        }

        return new Breakfast(
            id: id ?? Guid.NewGuid(),
            name: name,
            description: description,
            startDateTime: startDateTime,
            endDateTime: endDateTime,
            lastModifiedDateTime: DateTime.UtcNow,
            savory: savory,
            sweet: sweet);
    }
}
