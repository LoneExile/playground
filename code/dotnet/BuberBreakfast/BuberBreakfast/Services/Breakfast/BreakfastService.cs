using BuberBreakfast.Models;
using BuberBreakfast.ServicesErrors;
using ErrorOr;

namespace BuberBreakfast.Services.Breakfasts;

public class BreakfastService : IBreakfastService
{
    private static readonly Dictionary<Guid, Breakfast> _breakfasts = new();
    public ErrorOr<Created> CreateBreakfast(Breakfast breakfast)
    {
        _breakfasts.Add(breakfast.Id, breakfast);
        return Result.Created;
    }

    public ErrorOr<Deleted> DeleteBreakfast(Guid id)
    {
        _ = _breakfasts.Remove(id);
        return Result.Deleted;
    }

    public ErrorOr<Breakfast> GetBreakfast(Guid id)
    {
        if (_breakfasts.TryGetValue(id, out Breakfast? breakfast))
        {
            return breakfast;
        }
        return Errors.Breakfast.NotFound; // BuberBreakfast.ServicesErrors
    }

    public ErrorOr<UpsertBreakfast> UpsertBreakfast(Breakfast breakfast)
    {
        bool IsCreated = !_breakfasts.ContainsKey(breakfast.Id);
        _breakfasts[breakfast.Id] = breakfast;
        return new UpsertBreakfast(IsCreated);
    }
}

// NOTE:
// So, the impact of removing `static` depends on how you're managing the lifetime of `BreakfastService` instances.
// If you're using `AddSingleton`, the impact will be minimal. 
// If you're using `AddTransient` or `AddScoped`, the impact could be significant,
// depending on how you're using `BreakfastService`.
