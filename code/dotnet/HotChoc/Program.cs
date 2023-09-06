using System.Reflection;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddGraphQLServer()
    .AddQueryType<Query>();

builder.Services.AddOpenTelemetry()
                .ConfigureResource(resource => resource.AddService(
                            serviceNamespace: "openapi-demo-namespace",
                            serviceName: "openapi-demo-service",
                            serviceVersion: Assembly.GetEntryAssembly()?.GetName().Version?.ToString(),
                            serviceInstanceId: Environment.MachineName).AddAttributes(new Dictionary<string, object>
                                {
                                { "deployment.environment", "dev" },
                                { "deployment.version", "1.0.0" }
                                })).WithTracing(tracing => tracing.AddAspNetCoreInstrumentation()
                                .AddConsoleExporter()
                                .AddOtlpExporter())
                                    .WithMetrics(metrics => metrics.AddAspNetCoreInstrumentation()
                                            .AddRuntimeInstrumentation()
                                            .AddConsoleExporter()
                                            .AddOtlpExporter(opt =>
                                                {
                                                    // opt.Endpoint = new Uri("http://otel-collector:4317");
                                                    opt.Endpoint = new Uri("http://localhost:4317");
                                                }));


WebApplication app = builder.Build();

// app.MapGet("/", () => "Hello World!");
app.MapGraphQL();

app.Run();
