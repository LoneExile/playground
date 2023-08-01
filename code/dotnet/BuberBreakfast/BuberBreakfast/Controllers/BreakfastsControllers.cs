using BuberBreakfast.Contracts.Breakfast;
using BuberBreakfast.Models;
using BuberBreakfast.Services.Breakfasts;
using ErrorOr;
using Microsoft.AspNetCore.Mvc;

namespace BuberBreakfast.Controllers;

public class BreakfastsControllers : ApiController
{
    private readonly IBreakfastService _breakfastService;

    // NOTE: this is a dependency injection constructor
    public BreakfastsControllers(IBreakfastService breakfastService)
    {
        _breakfastService = breakfastService;
    }

    [HttpPost]
    public IActionResult CreateBreakfast(CreateBreakfastRequest request)
    {
        ErrorOr<Breakfast> requestToBreakfastResult = Breakfast.Create(
            name: request.Name,
            description: request.Description,
            startDateTime: request.StartDateTime,
            endDateTime: request.EndDateTime,
            savory: request.Savory,
            sweet: request.Sweet
        );

        if (requestToBreakfastResult.IsError)
        {
            return Problem(requestToBreakfastResult.Errors);
        }

        Breakfast breakfast = requestToBreakfastResult.Value;

        // TODO: save breakfast to database
        ErrorOr<Created> createdBreakfastResult = _breakfastService.CreateBreakfast(breakfast);

        // if (createdBreakfastResult.IsError)
        // {
        //     return Problem(createdBreakfastResult.Errors);
        // }

        // return CreateAtGetBreakfast(breakfast);

        return createdBreakfastResult.Match(
            created => CreateAtGetBreakfast(breakfast),
            errors => Problem(errors));
    }

    private IActionResult CreateAtGetBreakfast(Breakfast breakfast)
    {
        return CreatedAtAction(
            actionName: nameof(GetBreakfast),
            routeValues: new { id = breakfast.Id },
            value: MapBreakfastResponse(breakfast));
    }

    [HttpGet("{id:guid}")]
    public IActionResult GetBreakfast(Guid id)
    {
        ErrorOr<Breakfast> getBreakfastResult = _breakfastService.GetBreakfast(id);

        return getBreakfastResult.Match(
            breakfast => Ok(MapBreakfastResponse(breakfast)),
            errors => Problem(errors));

        // if (getBreakfastResult.IsError
        //     && getBreakfastResult.FirstError == Errors.Breakfast.NotFound)
        // {
        //     return NotFound();
        // }

        // Breakfast breakfast = getBreakfastResult.Value;
        // BreakfastResponse response = MapBreakfastResponse(breakfast);

        // return Ok(response);
    }

    [HttpPut("{id:guid}")]
    public IActionResult UpsertBreakfast(Guid id, UpsertBreakfastRequest request)
    {
        ErrorOr<Breakfast> requestToBreakfastResult = Breakfast.Create(
            name: request.Name,
            description: request.Description,
            startDateTime: request.StartDateTime,
            endDateTime: request.EndDateTime,
            savory: request.Savory,
            sweet: request.Sweet,
            id: id);

        if (requestToBreakfastResult.IsError)
        {
            return Problem(requestToBreakfastResult.Errors);
        }

        Breakfast breakfast = requestToBreakfastResult.Value;

        ErrorOr<UpsertBreakfast> upsertResult = _breakfastService.UpsertBreakfast(breakfast);

        // TODO: return 201 Created if a new breakfast was created, otherwise return 204 No Content

        return upsertResult.Match(
            upsertBreakfast => upsertBreakfast.IsCreated ? CreateAtGetBreakfast(breakfast) : NoContent(),
            errors => Problem(errors));
    }


    [HttpDelete("{id:guid}")]
    public IActionResult DeleteBreakfast(Guid id)
    {
        ErrorOr<Deleted> deleteBreakfastResult = _breakfastService.DeleteBreakfast(id);

        return deleteBreakfastResult.Match(
            deleted => NoContent(),
            errors => Problem(errors));
    }

    private static BreakfastResponse MapBreakfastResponse(Breakfast breakfast)
    {
        return new BreakfastResponse(
            Id: breakfast.Id,
            Name: breakfast.Name,
            Description: breakfast.Description,
            StartDateTime: breakfast.StartDateTime,
            EndDateTime: breakfast.EndDateTime,
            LastModifiedDateTime: breakfast.LastModifiedDateTime,
            Savory: breakfast.Savory,
            Sweet: breakfast.Sweet
        );
    }
}
