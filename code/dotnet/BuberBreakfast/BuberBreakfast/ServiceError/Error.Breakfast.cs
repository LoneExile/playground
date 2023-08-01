using ErrorOr;

namespace BuberBreakfast.ServicesErrors;


public static class Errors
{
    public static class Breakfast
    {
        public static Error NotFound => Error.NotFound(
            code: "Breakfast.NotFound.",
            description: "The breakfast you requested was not found.");

        public static Error InvalidName => Error.Validation(
            code: "Breakfast.InvalidName.",
            description: $"The name of the breakfast must be between "
                         + $"{Models.Breakfast.MinNameLength} and {Models.Breakfast.MaxNameLength} characters.");

        public static Error InvalidDescription => Error.Validation(
            code: "Breakfast.InvalidDescription.",
            description: $"The description of the breakfast must be between "
                         + $"{Models.Breakfast.MinDescriptionLength} and {Models.Breakfast.MaxDescriptionLength} characters.");
    }
}


