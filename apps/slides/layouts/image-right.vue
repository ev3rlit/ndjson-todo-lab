<template>
  <div class="slidev-layout lab-layout lab-image-right">
    <main class="lab-image-copy">
      <slot />
    </main>
    <aside class="lab-image-frame">
      <img v-if="$slidev.nav.currentLayout?.meta?.image" :src="$slidev.nav.currentLayout.meta.image" alt="" />
    </aside>
  </div>
</template>
