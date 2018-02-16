# .net Core 2.0 Web API deployed to QNAP Nas using Docker container on Container Station
The purpose of this simple project is to help devs like me that likes to host dot net core application in the intranet, using QNAP Container Station.
This application is just a wrapper around docker, with a custom user interface.


## Environment setup

- Windows 10 X64 Professional
- Docker for Windows 17.06.2
- Visual Studio 2017 Enterprise 15.5.4
- QNAP Nas TS-253A 4.3.4.0483
- Container Station 1.8.3031
- QNAP Docker Version 17.07.0-ce


## Project Creation
- Open Visual Studio > File > New > Project
- Select the project type  in Visual C# > .NET Core > ASP.NET Core Web Application
- Choose a name and location and confirm
- Select .NET Core version 2.0, Web API, Enable Docker Support with OS: Linux and confirm
- Right click on the Web project, go to Package > Package version and set any version you might want to use, note this is necessary because by default, even if the version is visible, this is not present in the project file, but this is needed for the deployment script


## Run the project locally
At this stage you should have the docker-compose project as startup project.
If you run the application using F5, you will notice in the output window that it will compile the solution but also will build the docker image and container in the local docker for windows.

Automatically your default browser will open, and you will be able to see the output of the default hard coded invocation of a GET request on the Values controller.

## Setup Secure connection from client machine
We will be using a certificate to automatically authenticate the client machine with the docker server running on the NAS.
Follow the steps below to do it:

1) Access *NAS Web page*
2) Open Container Station Application
3) On the left menu, go to *Preferences*
4) Open the section *Docker Certificate* on the top right
5) Click on the *Download* button to download a zip containing the needed certificates
6) Extract the content of the zip file in the folder *%USERPROFILE%/.docker*

## QNAP Container Station
The latest update of container station, updated both docker server and client, so the default Dockerfile can e used without the need of customization.

## Deployment process
Using the task *Publish* the script will automatically:
- Stop the existing container 
- Remove the existing container
- If not exists, create a new Network in the NAS, for a properly working bridge configuration, for this we will use _docker network create_
- Run docker create to build the image and the container
- The newly created container will be started

## Deployment PowerShell script
The deployment script is located under the _Build_ folder and is called _build.ps1_.

This file is self documented and contains all the tasks necessary to complete the deployment process.

To generate a random mac address I use [this tool](https://justynshull.com/macgen/macgen.php).

## Execute the deployment
My PowerShell script uses [PSake](https://github.com/psake/psake) to handle the deployment process.
To install Psake open PowerShell and execute the following command:

`Install-Package psake `

Move inside the folder containing the solution file and run the following command:

`Invoke-psake .\Build\build.ps1 publish `

This command will invoke the psake task inside the build.ps1 file named publish.
This task will trigger all the necessary steps to be able to deploy.

If you want to see which other tasks are available, check the content of the build.ps1 file or run the command:

`Invoke-psake .\Build\build.ps1 `

Now browse the following url, to view the Values controller result:

`http://192.168.0.142/api/values `

## Troubleshooting
If running the PowerShell script you receive this error: error MSB4236: The SDK 'Microsoft.Docker.Sdk' specified could not be found.