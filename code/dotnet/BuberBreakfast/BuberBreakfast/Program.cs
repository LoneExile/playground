using BuberBreakfast.Services.Breakfasts;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();

// NOTE:
//- AddSingleton means that we will only have one instance of BreakfastService
//- AddTransient means that we will have a new instance of BreakfastService every time we need it
//- AddScoped means that we will have one instance of BreakfastService per request
builder.Services.AddScoped<IBreakfastService, BreakfastService>();

WebApplication app = builder.Build();
app.UseExceptionHandler("/error");
app.UseHttpsRedirection();
app.MapControllers();
app.Run();
