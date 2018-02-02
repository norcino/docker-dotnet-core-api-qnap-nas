properties {
	$containerName = "QnapDockerCoreApi"
	$imageName = "webapi"
	$hostname = "api"
	$containerMacAddress = "00:0C:29:E8:24:F4"
	$containerIpAddress = "192.168.0.142"
	$gatewayIpAddress = "192.168.0.1"
	$subnet = "192.168.0.0/24"
	$baseDir = resolve-path .\..\
    $srcDir = $baseDir
    $solution = Join-Path $baseDir "\Application.sln"
	$projectDir = Join-Path $srcDir "\Application.Api"
	$project = Join-Path  $projectDir "\Application.Api.csproj"
	$buildDir = Join-Path  $baseDir "Build"
	$publishDir = Join-Path $baseDir "\obj\Docker\publish"
	$imageDestinationDir = ".\DockerImage"
	$dockerfile = Join-Path $projectDir "\Dockerfile"
	$projBaseDir = resolve-path .\..\
    $buildConfiguration = "Release"
	$containerUrl = "tcp://nas.home:2376"
	$logsVolumePath = "/share/Container/Logs"
	$local = $false
}

task default -depends help

# Builds, create the image, uploads it
task publish -depends check-docker-running, build, generate-image, create-container, start-container

task help {
	Exec { echo "" }
	Exec { echo "Example of execution:" }
	Exec { echo "" }
	Exec { echo "invoke-psake .\build.ps1 {task_name}" }
	Exec { echo "Use -properties @{local=$true} to override properties of the script" }
	Exec { echo "build:							Clean the solution, restores the nuget packages and builds the solution" }
	Exec { echo "publish:						Publishes the API"}	
	Exec { echo "clean:							Clean the solution"}
	Exec { echo "restore:						Restores nuget packages"}
	Exec { echo "generate-image:				If the image exists already with the same tag it is removed, then builds and publishes the solution and then Generates the image using the published content"}
	Exec { echo "stop-containers:				Stop all the remote containers using the image"}
	Exec { echo "start-container:				Start the newly created container"}
	Exec { echo "remove-container:				Remove all the remote containers with the same name"}
	Exec { echo "create-container:				Create the container using the latest version of the image"}
	Exec { echo "remove-containers:				Stops and Remove all the remote containers with the same name"}	
	Exec { echo "remove-image:					Remove existing image with the same tag"}
	Exec { echo "remove-images:					Removes all the remote images with the same name"}
	Exec { echo "publish-solution:				Build the solution and generates the solution publishing folder"}	
	Exec { echo "get-version:					Get the API version from project file"}	
	Exec { echo "create-container-network:		If doesn't exist, create the network used by all containers in the NAS"}	
}

# 
# ---------------------------------------------------------------------------------------------------------
#

# Clean the solution
task clean {
	Log("Cleaning API build")
    Exec { dotnet clean -c $buildConfiguration $solution }
}

# Clean the solution, restores the nuget packages and builds the solution
task build -depends clean, restore {
	Log("Building API application")
    Exec { dotnet build -c $buildConfiguration $solution }
}

# Restores nuget packages
task restore {
	Log("Restoring API source packages")
    Exec { dotnet restore $solution }
}

# Get the API version from project file
task get-version {
	Log("Getting current API version")
	
	[xml]$xml =  Get-Content $project
	$script:buildversion = Select-Xml "child::Project/PropertyGroup/Version" $xml
	Exec { "API version " + $script:buildversion }
}

# Generate the solution publishing folder
task publish-solution -depends build {
	Log("Generating publish folder")
	Write-Host $publishDir
    Exec { dotnet publish --output $publishDir $project -c $buildConfiguration }
}

# If the image exists already with the same tag it is removed, then builds and publishes the solution and then Generates the image using the published content
task generate-image -depends remove-image, publish-solution, get-version {
	Log("Building docker image")
    Exec { 
		if($local) {
			docker build -f $dockerfile -t $imageName":"$script:buildversion $baseDir 
		} else {
			Write-Host $dockerfile
			Write-Host $imageName
			Write-Host $script:buildversion
			Write-Host $baseDir
			docker --tls -H="$containerUrl" build -f $dockerfile -t $imageName":"$script:buildversion $baseDir 
		}		
	}
}

# Stop all the remote containers using the image
task stop-containers {		
	Log("Stopping existing docker containers")	
	Exec {
		if($local) {
			docker ps -a -f ancestor=$containerName --no-trunc -q | foreach-object { docker stop $_ }
			docker ps -a -f name=$containerName --no-trunc -q | foreach-object { docker stop $_ }
		} else {
			docker --tls -H="$containerUrl" ps -a -f ancestor=$containerName --no-trunc -q | foreach-object { docker --tls -H="$containerUrl" stop $_ }
			docker --tls -H="$containerUrl" ps -a -f name=$containerName --no-trunc -q | foreach-object { docker --tls -H="$containerUrl" stop $_ }
		}
	}
}

# Remove existing image with the same tag
task remove-image -depends force-docker-api-nas, remove-containers, get-version {
	Log("Removing existing docker image $($imageName):$($script:buildversion)")
	Exec {
		if($local) {
			$existingImages = docker images $imageName":"$script:buildversion
			
			If ($existingImages.count -gt 1) {
				write-host "Removing the existing image.."
				docker rmi -f $imageName":"$script:buildversion;
			} else {
				write-host "The image does not exist"
			}
		} else {
			$existingImages = docker --tls -H="$containerUrl" images $imageName":"$script:buildversion
			
			If ($existingImages.count -gt 1) {
				write-host "Removing the existing image.."
				docker --tls -H="$containerUrl" rmi -f $imageName":"$script:buildversion;
			} else {
				write-host "The image does not exist"
			}
		}		
	}
}

# Removes all the remote images with the same name
task remove-images -depends stop-containers {
	Log("Removing existing docker images")
	Exec { 
		$images = @();
		$imagestoremove = @();

		if($local) {
			docker images -a | foreach-object { $data = $_ -split '\s+';
				$image = new-object psobject
				$image | add-member -type noteproperty -Name "Repository" -value $data[0]
				$image | add-member -type noteproperty -Name "Tag" -value $data[1]
				$image | add-member -type noteproperty -Name "Image" -value $data[2]
				$images += $image 
			};

			$imagestoremove = $images | Where-Object { 
				$_.Repository.StartsWith($imageName) -or $_.Tag.StartsWith($imageName) -or $_.Tag -eq "<none>" -or $_.Repository -eq "<none>"
			} | select Image;
			
			$imagestoremove | foreach-object { docker rmi -f $_.Image };
		} else {
			docker --tls -H="$containerUrl" images -a | foreach-object { $data = $_ -split '\s+';
				$image = new-object psobject
				$image | add-member -type noteproperty -Name "Repository" -value $data[0]
				$image | add-member -type noteproperty -Name "Tag" -value $data[1]
				$image | add-member -type noteproperty -Name "Image" -value $data[2]
				$images += $image 
			};

			$imagestoremove = $images | Where-Object { 
				$_.Repository.StartsWith($imageName) -or $_.Tag.StartsWith($imageName) -or $_.Tag -eq "<none>" -or $_.Repository -eq "<none>"
			} | select Image;
			
			$imagestoremove | foreach-object { docker --tls -H="$containerUrl" rmi -f $_.Image };
		}
	}
}

# Stops and Remove all the remote containers with the same name
task remove-containers -depends stop-containers {		
	Log("Removing docker cointainers")
	Exec {
		if($local) {
			docker ps -a -f ancestor=$containerName* --no-trunc -q | foreach-object { docker rm -f $_ }
			docker ps -a -f name=$containerName* --no-trunc -q | foreach-object { docker rm -f $_ }
		} else {
			docker --tls -H="$containerUrl" ps -a -f ancestor=$containerName* --no-trunc -q | foreach-object { docker --tls -H="$containerUrl" rm -f $_ }
			docker --tls -H="$containerUrl" ps -a -f name=$containerName* --no-trunc -q | foreach-object { docker --tls -H="$containerUrl" rm -f $_ }
		}
	}
}

# Create the network used by the container
task create-container-network -precondition { return -Not $local } {
	Log("Create the network used by the container")
	Exec {
		$existingnetworks = docker --tls -H="$containerUrl" network ls -f 'name=bridged-network'
				
		If ($existingnetworks.count -gt 1) {
			write-host "Network container already exists"
		} Else {
			docker --tls -H="$containerUrl" network create --driver "qnet" -d qnet --ipam-driver=qnet --ipam-opt=iface=eth0 --subnet $subnet --gateway $gatewayIpAddress bridged-network
		}
	}
}

# Start the newly created container
task start-container {
	Log("Start the newly created container")
	Exec { 
		if($local) {
			docker start $containerName
		} else {
			docker --tls -H="$containerUrl" start $containerName
		}
	}
}

# Create the container using the latest version of the image
task create-container -depends get-version, remove-containers, create-container-network {
	Log("Creating the container")
	Exec {
		if($local) {
			docker `
				create `
				--hostname $hostname `
				--name $containerName `
				--net bridge `
				--workdir '/app' `
				--publish-all=true `
				--publish "0.0.0.0::80" `
				-t `
				-i $imageName":"$script:buildversion
		} else {
			docker --tls -H="$containerUrl" `
				create `
				--hostname $hostname `
				--name $containerName `
				--mac-address=$containerMacAddress `
				--ip $containerIpAddress `
				--net "bridged-network" `
				--workdir '/app' `
				--publish-all=true `
				--volume "$($logsVolumePath):/app/Logs:rw" `
				--publish "0.0.0.0::80" `
				-t `
				-i $imageName":"$script:buildversion			
		}
	}
}

# Overrides the local docker API version to be compatible with the remote server's version
task force-docker-api-nas -precondition { return -Not $local } {
	Log("Forcing docker client API to version 1.23")
	Exec { $env:DOCKER_API_VERSION = 1.23 }
}

#
# ---------------------------------------------------------------------------------------------------------
#

# Helper function to log in console the list of operations
function Log ($msg)
{
	write-host ""
	write-host "----------------------------------------------------------"
	write-host $msg -foreground "Magenta"
	write-host "----------------------------------------------------------"
	write-host ""
}

# Check that docker is running on target machine
task check-docker-running -depends force-docker-api-nas {

	Try
	{
		Exec { docker ps }
	}
	Catch
	{
		Log("Docker is not running in the local machine")
		break
	}    
	
	Try
	{
		if(-Not $local) { 
			Exec { docker --tls -H="$containerUrl" ps }
		}
	}
	Catch
	{
		Log("Unable to access Docker on target machine, check that docker is running and that the url is correct")
		break
	}    
}