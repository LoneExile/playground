# Use the SDK image to build the app
FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build-env
WORKDIR /src
COPY *.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet publish -c Release -o out

# Build runtime image
FROM mcr.microsoft.com/dotnet/aspnet:6.0
WORKDIR /app
COPY --from=build-env /src/out .
EXPOSE 5000
ENV ASPNETCORE_URLS=http://*:5000

ENTRYPOINT ["dotnet", "HotChoc.dll"]

