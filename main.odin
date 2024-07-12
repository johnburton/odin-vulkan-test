package main

import fmt  "core:fmt"
import glfw "vendor:glfw"
import vk   "vendor:vulkan"

FRAMES_IN_FLIGHT :: 2

window              : glfw.WindowHandle
instance            : vk.Instance
physical_device     : vk.PhysicalDevice
surface             : vk.SurfaceKHR
device              : vk.Device
queue_family        : u32
queue               : vk.Queue
swapchain           : vk.SwapchainKHR
images              : [dynamic]vk.Image
image_views         : [dynamic]vk.ImageView

command_pool        : [FRAMES_IN_FLIGHT]vk.CommandPool
command_buffer      : [FRAMES_IN_FLIGHT]vk.CommandBuffer
fence               : [FRAMES_IN_FLIGHT]vk.Fence
swapchain_semaphore : [FRAMES_IN_FLIGHT]vk.Semaphore
render_semaphore    : [FRAMES_IN_FLIGHT]vk.Semaphore

main :: proc() {
	initialize_main_window()
	initialize_vulkan_instance()
	initialize_vulkan_physical_device()
	initialize_vulkan_surface()
	initialize_vulkan_device()
	initialize_vulkan_swapchain()
	initialize_vulkan_per_frame()
	run_event_loop()
}

check_vk :: proc(result: vk.Result, location := #caller_location) {
	if result != .SUCCESS {
		fmt.panicf("Vulkan error: {} @ {}\n", result, location)
	}
}

initialize_main_window :: proc () {
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window = glfw.CreateWindow(2800, 1600, "HELLO WORLD", nil, nil)
}

initialize_vulkan_instance :: proc() {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	layers := []cstring {
		"VK_LAYER_KHRONOS_validation"
	}

	extensions : [dynamic]cstring
	defer delete (extensions)
	for extension_name in glfw.GetRequiredInstanceExtensions() {
		append(&extensions, extension_name)
	}

	instance_create_info: vk.InstanceCreateInfo
	instance_create_info.sType = .INSTANCE_CREATE_INFO
	instance_create_info.enabledLayerCount = u32(len(layers))
	instance_create_info.ppEnabledLayerNames = raw_data(layers)
	instance_create_info.enabledExtensionCount = u32(len(extensions))
	instance_create_info.ppEnabledExtensionNames = raw_data(extensions)
	check_vk(vk.CreateInstance(&instance_create_info, nil, &instance))

	vk.load_proc_addresses(instance)
}

initialize_vulkan_physical_device :: proc() {
	physical_device_count: u32
	check_vk(vk.EnumeratePhysicalDevices(instance, &physical_device_count, nil))
	fmt.printf("Found {} physical devices\n", physical_device_count)

	physical_devices := make([dynamic]vk.PhysicalDevice, physical_device_count)
	defer delete (physical_devices)
	check_vk(vk.EnumeratePhysicalDevices(instance, &physical_device_count, raw_data(physical_devices)))

	best_score := 0
	for device, index in physical_devices {
		physical_device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &physical_device_properties)

		score := 0
		if physical_device_properties.deviceType == .DISCRETE_GPU do score += 900
		if physical_device_properties.deviceType == .INTEGRATED_GPU do score += 400
		if physical_device_properties.deviceType == .CPU do score += 100

		fmt.printf(" - Physical device {} score {}: {}\n", index, score, cstring(&physical_device_properties.deviceName[0]))

		if score > best_score {
			best_score = score
			physical_device = device
		}
	}
}

initialize_vulkan_surface :: proc() {
	check_vk(glfw.CreateWindowSurface(instance, window, nil, &surface))
}

initialize_vulkan_device :: proc() {

	extensions := []cstring {
		"VK_KHR_swapchain"	
	}

	queue_priorities : f32 = 1.0

	queue_info: vk.DeviceQueueCreateInfo
	queue_info.sType = .DEVICE_QUEUE_CREATE_INFO
	queue_info.queueFamilyIndex = queue_family
	queue_info.queueCount = 1
	queue_info.pQueuePriorities = &queue_priorities

	device_create_info: vk.DeviceCreateInfo
	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.queueCreateInfoCount = 1
	device_create_info.pQueueCreateInfos = &queue_info
	device_create_info.enabledExtensionCount = u32(len(extensions))
	device_create_info.ppEnabledExtensionNames = raw_data(extensions)
	check_vk(vk.CreateDevice(physical_device, &device_create_info, nil, &device))

	// Now get the queue that was create
	vk.GetDeviceQueue(device, queue_family, 0, &queue)
}

initialize_vulkan_swapchain :: proc() {
	extent := vk.Extent2D {2800, 1600}

	swapchain_create_info: vk.SwapchainCreateInfoKHR
	swapchain_create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR
	swapchain_create_info.compositeAlpha = { .OPAQUE }
	swapchain_create_info.imageArrayLayers = 1
	swapchain_create_info.imageColorSpace = .SRGB_NONLINEAR
	swapchain_create_info.surface = surface
	swapchain_create_info.imageUsage = { .COLOR_ATTACHMENT }
	swapchain_create_info.imageFormat = .B8G8R8A8_UNORM
	swapchain_create_info.preTransform = { .IDENTITY }
	swapchain_create_info.imageExtent = extent
	swapchain_create_info.minImageCount = 3

	check_vk(vk.CreateSwapchainKHR(device, &swapchain_create_info, nil, &swapchain))

	// Get the swapchain images
	swapchain_image_count: u32
	vk.GetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, nil)
	fmt.printf("Swapchain has {} images\n", swapchain_image_count)

	images := make([dynamic]vk.Image, swapchain_image_count)
	defer delete(images)
	vk.GetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, raw_data(images))

	// Create image views
	for i : u32 = 0; i < swapchain_image_count; i += 1 {
		image_view: vk.ImageView
		image_view_create_info: vk.ImageViewCreateInfo
		image_view_create_info.sType = .IMAGE_VIEW_CREATE_INFO
		image_view_create_info.viewType = .D2
		image_view_create_info.format = .B8G8R8A8_UNORM
		image_view_create_info.image = images[i]
		image_view_create_info.subresourceRange.aspectMask = { .COLOR }
		image_view_create_info.subresourceRange.layerCount = 1
		image_view_create_info.subresourceRange.levelCount = 1

		check_vk(vk.CreateImageView(device, &image_view_create_info, nil, &image_view))
		append(&image_views, image_view)
	}
}

initialize_vulkan_per_frame :: proc () {

	for frame in 0 ..< FRAMES_IN_FLIGHT {
		command_pool_create_info: vk.CommandPoolCreateInfo
		command_pool_create_info.sType = .COMMAND_POOL_CREATE_INFO
		command_pool_create_info.queueFamilyIndex = queue_family
		command_pool_create_info.flags = { .RESET_COMMAND_BUFFER }
   	    check_vk(vk.CreateCommandPool(device, &command_pool_create_info, nil, &command_pool[frame]))

   	    command_buffer_allocate_info: vk.CommandBufferAllocateInfo
   	    command_buffer_allocate_info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
   	    command_buffer_allocate_info.commandPool = command_pool[frame]
   	    command_buffer_allocate_info.level = .PRIMARY
   	    command_buffer_allocate_info.commandBufferCount = 1
   	    check_vk(vk.AllocateCommandBuffers(device, &command_buffer_allocate_info, &command_buffer[frame]))

   	    fence_create_info: vk.FenceCreateInfo
   	    fence_create_info.sType = .FENCE_CREATE_INFO
   	   	fence_create_info.flags = { .SIGNALED }
   	    check_vk(vk.CreateFence(device, &fence_create_info, nil, &fence[frame]))

   	    semaphore_create_info: vk.SemaphoreCreateInfo
   	    semaphore_create_info.sType = .SEMAPHORE_CREATE_INFO

   	    check_vk(vk.CreateSemaphore(device, &semaphore_create_info, nil, &swapchain_semaphore[frame]))
   	    check_vk(vk.CreateSemaphore(device, &semaphore_create_info, nil, &render_semaphore[frame]))
   	}
}



run_event_loop :: proc() {
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
	}

}
