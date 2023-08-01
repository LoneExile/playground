using ErrorOr;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace BuberBreakfast.Controllers;

// NOTE:
// [Route("breakfasts")]
// we can change it to [Route("api/breakfasts")] or [Route("api/[controller]")]
// [Route("[controller]")] is a token that will be replaced with the name of the controller, in this case BreakfastsControllers
// http://localhost:5051/BreakfastsControllers

[ApiController]
[Route("[controller]")]
public class ApiController : ControllerBase
{
    // NOTE: protected means that it can be accessed by the class itself and by derived classes
    protected IActionResult Problem(List<Error> errors)
    {
        if (errors.All(e => e.Type == ErrorType.Validation))
        {
            ModelStateDictionary modelStateDictionary = new();

            foreach (Error error in errors)
            {
                modelStateDictionary.AddModelError(error.Code, error.Description);
            }

            return ValidationProblem(modelStateDictionary);
        }

        if (errors.Any(e => e.Type == ErrorType.Unexpected))
        {
            return Problem();
        }

        Error firstError = errors[0];

        int statusCode = firstError.Type switch
        {
            ErrorType.NotFound => StatusCodes.Status404NotFound,
            ErrorType.Validation => StatusCodes.Status400BadRequest,
            ErrorType.Conflict => StatusCodes.Status409Conflict,
            // ErrorType.Failure => StatusCodes.Status500InternalServerError,
            // ErrorType.Unexpected => StatusCodes.Status500InternalServerError,
            _ => StatusCodes.Status500InternalServerError
        };

        return Problem(statusCode: statusCode, title: firstError.Description);
    }

}

