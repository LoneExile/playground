# REST API using .NET 6 with ErrorOr

```bash
## create a new project
dotnet new sln -o BuberBreakfast
cd BuberBreakfast

## create a new class library project
dotnet new classlib -o BuberBreakfast.Contracts

## create a new web API project
dotnet new webapi -o BuberBreakfast

## add the projects to the solution
dotnet sln add $(find . -name "*.csproj")
# dotnet sln add BuberBreakfast.Contracts BuberBreakfast/

## add a reference to the contracts project to the web API project
dotnet add ./BuberBreakfast reference ./BuberBreakfast.Contracts/

## Running the project
dotnet run --project ./BuberBreakfast
# dotnet watch run --no-hot-reload --project ./BuberBreakfast

```

Creating two separate projects, one for the contracts (interfaces, models, DTOs,
etc.) and one for the actual web API, is a common practice in larger, more
complex applications for a few reasons SOC, Reusability, Versioning, Testing.

This project uses the [ErrorOr](https://github.com/amantinband/error-or)

```bash
dotnet add ./BuberBreakfast package ErrorOr
```

ErrorOr is a library that provides a generic type, `ErrorOr<T>`, that can be
used to represent a value that can either be a value of type `T` or an error.
(Alternative?:
[FluentValidation](https://github.com/FluentValidation/FluentValidation))

For more general-purpose error handling, the built-in exception handling
mechanism in .NET is widely used. This includes the `try`, `catch`, `finally`
blocks and the `throw` statement for raising exceptions.

> 📍Conclusion: ErrorOr makes me think of golang's error handling mechanism and
> how it's a bit more explicit than .NET's exception handling mechanism.
